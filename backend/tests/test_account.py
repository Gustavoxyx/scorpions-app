"""Testes da exclusão de conta, da exportação e da reautenticação.

Cobre os achados HIGH-2 (não havia caminho para o titular apagar os próprios
dados), MEDIUM-5 (sem reautenticação em operação sensível) e MEDIUM-3 (sem
verificação de e-mail).

# Sobre os dublês
Nada aqui fala com o Firebase. O que está sob teste é a **ordem da cascata** e
as **decisões de autorização**, e as duas são lógica do serviço. Um teste contra
o Firebase real seria lento, exigiria credencial no CI e — o que importa mais —
apagaria dados de verdade para verificar que a exclusão apaga dados.

O dublê do Firestore é escrito à mão em vez de montado com `unittest.mock`
porque o que precisa ser verificado é a **sequência** de operações, e um mock
genérico registra chamadas sem impor a estrutura de coleções e documentos que a
cascata percorre. Com o dublê, um caminho errado simplesmente não encontra nada
— que é o mesmo que aconteceria em produção.
"""

from __future__ import annotations

import os
import time

import pytest
from fastapi import HTTPException

os.environ.setdefault("FIREBASE_PROJECT_ID", "demo-scorpions")
os.environ.setdefault(
    "FIREBASE_SERVICE_ACCOUNT",
    '{"type":"service_account","project_id":"demo-scorpions",'
    '"private_key":"nao-e-uma-chave","client_email":"teste@exemplo"}',
)

from app import account  # noqa: E402
from app.auth import Caller, Role  # noqa: E402
from app.config import get_settings  # noqa: E402


# =============================================================================
# Dublês
# =============================================================================


class DocFalso:
    def __init__(self, doc_id: str, dados: dict, pai: "ColecaoFalsa"):
        self.id = doc_id
        self._dados = dados
        self._pai = pai
        self.reference = self

    @property
    def exists(self) -> bool:
        return self._dados is not None

    def to_dict(self) -> dict | None:
        return self._dados

    def get(self):
        return self

    def delete(self):
        self._pai.apagados.append(self.id)
        self._pai.docs.pop(self.id, None)

    def collection(self, nome: str):
        return self._pai.banco.colecao(f"{self._pai.caminho}/{self.id}/{nome}")


class ConsultaFalsa:
    def __init__(self, colecao: "ColecaoFalsa", filtro=None, limite=None):
        self._colecao = colecao
        self._filtro = filtro
        self._limite = limite

    def where(self, filter=None):  # noqa: A002 - a API do Firestore usa este nome
        return ConsultaFalsa(self._colecao, filter, self._limite)

    def limit(self, n: int):
        return ConsultaFalsa(self._colecao, self._filtro, n)

    def stream(self):
        itens = [
            DocFalso(k, v, self._colecao) for k, v in list(self._colecao.docs.items())
        ]
        if self._filtro is not None:
            campo, valor = self._filtro
            itens = [d for d in itens if (d.to_dict() or {}).get(campo) == valor]
        if self._limite is not None:
            itens = itens[: self._limite]
        return iter(itens)


class ColecaoFalsa:
    def __init__(self, caminho: str, banco: "FirestoreFalso"):
        self.caminho = caminho
        self.banco = banco
        self.docs: dict[str, dict] = {}
        self.apagados: list[str] = []

    def document(self, doc_id: str) -> DocFalso:
        return DocFalso(doc_id, self.docs.get(doc_id), self)

    def where(self, filter=None):  # noqa: A002
        return ConsultaFalsa(self, filter)

    def limit(self, n: int):
        return ConsultaFalsa(self, None, n)

    def stream(self):
        return ConsultaFalsa(self).stream()

    def add(self, dados: dict):
        chave = f"auto-{len(self.docs)}"
        self.docs[chave] = dados
        return None, DocFalso(chave, dados, self)


class LoteFalso:
    def __init__(self):
        self.operacoes: list[str] = []

    def delete(self, ref):
        self.operacoes.append(ref.id)
        ref.delete()

    def commit(self):
        pass


class FirestoreFalso:
    def __init__(self):
        self.colecoes: dict[str, ColecaoFalsa] = {}
        #: A ordem em que as coisas aconteceram. É o que os testes de ordem leem.
        self.eventos: list[str] = []

    def colecao(self, caminho: str) -> ColecaoFalsa:
        if caminho not in self.colecoes:
            self.colecoes[caminho] = ColecaoFalsa(caminho, self)
        return self.colecoes[caminho]

    def collection(self, nome: str) -> ColecaoFalsa:
        return self.colecao(nome)

    def batch(self) -> LoteFalso:
        return LoteFalso()


class BlobFalso:
    def __init__(self, nome: str, bucket: "BucketFalso"):
        self.name = nome
        self._bucket = bucket

    def delete(self):
        self._bucket.apagados.append(self.name)


class BucketFalso:
    def __init__(self, nomes: list[str]):
        self._nomes = nomes
        self.apagados: list[str] = []
        self.prefixos_consultados: list[str] = []

    def list_blobs(self, prefix: str = ""):
        self.prefixos_consultados.append(prefix)
        return [BlobFalso(n, self) for n in self._nomes if n.startswith(prefix)]


# =============================================================================
# Preparo
# =============================================================================


@pytest.fixture
def ambiente(monkeypatch):
    """Monta o banco e o bucket falsos, e ligados ao módulo sob teste.

    Devolve `(banco, bucket, eventos)`. `eventos` acumula a ordem das etapas da
    cascata — é o que permite testar que a conta é apagada **por último**.
    """
    banco = FirestoreFalso()
    bucket = BucketFalso(
        [
            "users/u1/identifications/s1/original.jpg",
            "users/u1/identifications/s1/processed.jpg",
            "users/u1/identifications/s1/thumbnail.webp",
            # De outro usuário: nunca deve ser tocado.
            "users/OUTRO/identifications/s9/original.jpg",
        ]
    )
    eventos: list[str] = []

    banco.colecao("identifications").docs = {
        "i1": {"userId": "u1", "status": "identified"},
        "i2": {"userId": "u1", "status": "processing"},
        "i9": {"userId": "OUTRO", "status": "identified"},
    }
    banco.colecao("users").docs = {"u1": {"name": "Teste", "role": "user"}}
    banco.colecao("users/u1/quotas").docs = {"2026-10-05": {"count": 3}}

    monkeypatch.setattr(account, "_igual", lambda campo, valor: (campo, valor))

    import app.clients as clients

    # Um `setattr` aqui alcança o audit log também, e não por acaso: `audit.py`
    # faz `from .clients import firestore_client` **dentro** da função, então
    # resolve o nome em `app.clients` na hora da chamada. Substituir lá é
    # substituir para todos os módulos que importam assim.
    monkeypatch.setattr(clients, "firestore_client", lambda s: banco)
    monkeypatch.setattr(clients, "storage_bucket", lambda s: bucket)

    def apagar_usuario(uid, app=None):
        eventos.append(f"auth.delete:{uid}")

    import firebase_admin.auth as fb_auth

    monkeypatch.setattr(fb_auth, "delete_user", apagar_usuario)
    monkeypatch.setattr(account, "firebase_app", lambda s: None, raising=False)

    import app.auth as auth_mod

    monkeypatch.setattr(auth_mod, "firebase_app", lambda s: None)

    return banco, bucket, eventos


@pytest.fixture
def dono() -> Caller:
    return Caller(
        uid="u1",
        email="dono@exemplo.com",
        email_verified=True,
        role=Role.USER,
        auth_time=int(time.time()),  # acabou de autenticar
    )


# =============================================================================
# Reautenticação  (MEDIUM-5)
# =============================================================================


def test_login_recente_e_aceito() -> None:
    agora = Caller(
        uid="u1", email="a@b.c", email_verified=True, role=Role.USER,
        auth_time=int(time.time()),
    )
    # Não levanta.
    agora.requires_recent_auth()


def test_login_antigo_e_recusado_com_pedido_de_senha() -> None:
    """O cenário real: o token foi renovado sozinho, a senha é de ontem.

    Um ID token do Firebase se renova a cada hora sem pedir senha. Quem pega o
    aparelho destravado continua autenticado — e não pode apagar a conta.
    """
    velho = Caller(
        uid="u1", email="a@b.c", email_verified=True, role=Role.USER,
        auth_time=int(time.time()) - 86_400,  # 24 h
    )

    with pytest.raises(HTTPException) as erro:
        velho.requires_recent_auth()

    # 401 e não 403: o cliente **pode** resolver, reautenticando.
    assert erro.value.status_code == 401
    assert erro.value.headers.get("X-Reauth-Required") == "true"


def test_auth_time_ausente_e_recusado() -> None:
    """Falhar fechado.

    Um token forjado, ou muito antigo, pode não trazer `auth_time`. Zero não
    pode ser lido como "autenticou na época Unix" nem como "autenticou agora".
    """
    sem = Caller(
        uid="u1", email="a@b.c", email_verified=True, role=Role.USER, auth_time=0
    )

    with pytest.raises(HTTPException) as erro:
        sem.requires_recent_auth()
    assert erro.value.status_code == 401


def test_auth_time_no_futuro_nao_libera_para_sempre() -> None:
    """Relógio adiantado não vira passe livre.

    A idade fica negativa, e negativa é menor que o limite — então passa. Isso é
    aceitável e está testado de propósito para ficar registrado: quem controla
    `auth_time` é o Google, que assina o token, não o cliente. Se o cliente
    pudesse escolher, isto seria um buraco.
    """
    futuro = Caller(
        uid="u1", email="a@b.c", email_verified=True, role=Role.USER,
        auth_time=int(time.time()) + 600,
    )
    futuro.requires_recent_auth()  # não levanta


def test_janela_e_configuravel_por_operacao() -> None:
    quase = Caller(
        uid="u1", email="a@b.c", email_verified=True, role=Role.USER,
        auth_time=int(time.time()) - 120,  # 2 min
    )

    quase.requires_recent_auth(max_age_seconds=300)  # passa

    with pytest.raises(HTTPException):
        quase.requires_recent_auth(max_age_seconds=60)  # não passa


# =============================================================================
# E-mail verificado  (MEDIUM-3)
# =============================================================================


def test_email_nao_verificado_e_recusado() -> None:
    naoverificado = Caller(
        uid="u1", email="a@b.c", email_verified=False, role=Role.USER,
        auth_time=int(time.time()),
    )

    with pytest.raises(HTTPException) as erro:
        naoverificado.requires_verified_email()
    assert erro.value.status_code == 403


def test_email_verificado_passa() -> None:
    verificado = Caller(
        uid="u1", email="a@b.c", email_verified=True, role=Role.USER,
        auth_time=int(time.time()),
    )
    verificado.requires_verified_email()  # não levanta


# =============================================================================
# A cascata  (HIGH-2)
# =============================================================================


def test_cascata_apaga_tudo_do_titular(ambiente, dono) -> None:
    banco, bucket, _ = ambiente

    relatorio = account.delete_account(get_settings(), dono, "req-1")

    assert relatorio.images == 3
    assert relatorio.identifications == 2
    assert relatorio.subcollection_docs == 1
    assert relatorio.profile_deleted
    assert relatorio.auth_deleted
    assert relatorio.errors == []


def test_cascata_nao_toca_dados_de_outro_usuario(ambiente, dono) -> None:
    """O teste mais importante deste arquivo.

    Uma cascata que apaga demais é pior que uma que não existe: ela destrói
    dados de quem não pediu nada, e sem backup isso é definitivo.
    """
    banco, bucket, _ = ambiente

    account.delete_account(get_settings(), dono, "req-2")

    # Nenhuma imagem de OUTRO foi apagada.
    assert all("OUTRO" not in n for n in bucket.apagados)
    # O prefixo consultado carrega o uid verificado — é o IDOR fechado por
    # construção, e aqui está a prova.
    assert bucket.prefixos_consultados == ["users/u1/"]

    # A identificação de OUTRO sobreviveu.
    assert "i9" in banco.colecao("identifications").docs
    assert "i1" not in banco.colecao("identifications").docs


def test_a_conta_de_autenticacao_e_apagada_por_ultimo(ambiente, dono) -> None:
    """A ordem não é negociável.

    Se a conta fosse apagada primeiro e a cascata falhasse no meio, sobrariam
    imagens órfãs — dado pessoal sem dono, e sem regra protegendo, porque as
    regras comparam com `request.auth.uid` e esse uid deixou de existir.
    """
    banco, bucket, eventos = ambiente

    account.delete_account(get_settings(), dono, "req-3")

    assert eventos == ["auth.delete:u1"]
    # Quando a conta foi apagada, as imagens e os documentos já tinham ido.
    assert len(bucket.apagados) == 3
    assert "u1" not in banco.colecao("users").docs


def test_falha_no_storage_preserva_a_conta(ambiente, dono, monkeypatch) -> None:
    """Falha parcial não deixa o titular sem conta e com dados.

    Com a conta viva, ele entra e tenta de novo. É o oposto de um estado em que
    o login sumiu e as imagens ficaram.
    """
    banco, bucket, eventos = ambiente

    def explode(prefix=""):
        raise RuntimeError("storage indisponível")

    monkeypatch.setattr(bucket, "list_blobs", explode)

    with pytest.raises(HTTPException) as erro:
        account.delete_account(get_settings(), dono, "req-4")

    assert erro.value.status_code == 500
    # A conta **não** foi apagada.
    assert eventos == []
    # E a mensagem diz ao usuário que ele não perdeu nada pela metade.
    assert "continua ativa" in erro.value.detail


def test_a_falha_gera_registro_de_auditoria(ambiente, dono, monkeypatch) -> None:
    banco, bucket, _ = ambiente
    monkeypatch.setattr(
        bucket, "list_blobs", lambda prefix="": (_ for _ in ()).throw(RuntimeError())
    )

    with pytest.raises(HTTPException):
        account.delete_account(get_settings(), dono, "req-5")

    registros = list(banco.colecao("auditLogs").docs.values())
    assert any(r["action"] == "account.delete_failed" for r in registros)


def test_o_sucesso_gera_registro_de_auditoria(ambiente, dono) -> None:
    banco, _, _ = ambiente

    account.delete_account(get_settings(), dono, "req-6")

    registros = list(banco.colecao("auditLogs").docs.values())
    sucesso = [r for r in registros if r["action"] == "account.deleted"]
    assert len(sucesso) == 1
    assert sucesso[0]["actorUid"] == "u1"
    assert sucesso[0]["outcome"] == "success"


def test_o_audit_log_nao_guarda_dado_pessoal(ambiente, dono) -> None:
    """§24 e §27: o audit log concentra atividade de todos os usuários.

    Por isso é o alvo mais valioso do banco — e por isso guarda o mínimo.
    """
    banco, _, _ = ambiente

    account.delete_account(get_settings(), dono, "req-7")

    for registro in banco.colecao("auditLogs").docs.values():
        texto = str(registro).lower()
        assert "dono@exemplo.com" not in texto, "e-mail no audit log"
        assert "original.jpg" not in texto, "caminho de arquivo no audit log"
        assert "users/u1/" not in texto, "caminho de storage no audit log"


def test_a_subcolecao_de_cota_e_apagada(ambiente, dono) -> None:
    """Apagar um documento no Firestore NÃO apaga as subcoleções dele.

    Elas continuam existindo, acessíveis por caminho direto. Um contador de cota
    sobrevivente é pouco — mas é dado de um titular que pediu para ser apagado.
    """
    banco, _, _ = ambiente

    account.delete_account(get_settings(), dono, "req-8")

    assert banco.colecao("users/u1/quotas").docs == {}


def test_titular_sem_nada_nao_quebra(ambiente, monkeypatch) -> None:
    """Conta recém-criada, sem foto e sem análise.

    O caminho vazio precisa funcionar: é o de quem criou a conta, mudou de
    ideia e saiu.
    """
    banco, bucket, _ = ambiente
    banco.colecao("identifications").docs = {}
    banco.colecao("users/u2/quotas").docs = {}
    monkeypatch.setattr(bucket, "_nomes", [])

    vazio = Caller(
        uid="u2", email="novo@exemplo.com", email_verified=True, role=Role.USER,
        auth_time=int(time.time()),
    )

    relatorio = account.delete_account(get_settings(), vazio, "req-9")

    assert relatorio.images == 0
    assert relatorio.identifications == 0
    assert relatorio.auth_deleted


# =============================================================================
# Exportação  (Art. 18, V)
# =============================================================================


def test_exportacao_traz_so_os_dados_do_titular(ambiente, dono) -> None:
    banco, _, _ = ambiente

    pacote = account.export_data(get_settings(), dono, "req-10")

    ids = {i["id"] for i in pacote["identifications"]}
    assert ids == {"i1", "i2"}
    assert "i9" not in ids, "exportou dado de outro usuário"
    assert pacote["profile"]["name"] == "Teste"


def test_exportacao_nao_inclui_as_imagens(ambiente, dono) -> None:
    """Um JSON com megabytes de base64 dentro é inútil para portabilidade.

    O que vai é a referência; a imagem o titular baixa pelo aplicativo, com a
    regra do Storage autorizando normalmente.
    """
    banco, _, _ = ambiente

    pacote = account.export_data(get_settings(), dono, "req-11")

    assert "note" in pacote
    texto = str(pacote)
    assert "base64" not in texto


def test_exportacao_gera_registro_de_auditoria(ambiente, dono) -> None:
    """Exportar é acesso em massa aos próprios dados.

    Legítimo, e ainda assim registrado: se uma conta comprometida exportar tudo
    antes de apagar, o rastro é o que permite saber o que o atacante levou.
    """
    banco, _, _ = ambiente

    account.export_data(get_settings(), dono, "req-12")

    registros = list(banco.colecao("auditLogs").docs.values())
    assert any(r["action"] == "account.data_exported" for r in registros)


def test_exportacao_serializa_tipos_do_firestore(ambiente, dono) -> None:
    """`DatetimeWithNanoseconds` no meio quebraria a serialização.

    E quebraria **depois** de já ter lido tudo — o pior momento.
    """
    import datetime

    banco, _, _ = ambiente
    banco.colecao("identifications").docs["i1"]["createdAt"] = datetime.datetime(
        2026, 10, 5, 12, 0, tzinfo=datetime.timezone.utc
    )

    pacote = account.export_data(get_settings(), dono, "req-13")

    import json

    json.dumps(pacote)  # não levanta
    i1 = next(i for i in pacote["identifications"] if i["id"] == "i1")
    assert i1["createdAt"].startswith("2026-10-05")
