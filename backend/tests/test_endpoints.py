"""Testes dos endpoints, pela porta da frente.

Os outros arquivos testam as peças — cota, cascata, validação de imagem — cada
uma por si. Este testa que elas estão **ligadas**: que `DELETE /v1/me` de fato
exige senha recente, que a análise de fato cobra cota, que ninguém entra sem
token.

A diferença importa. Uma função `requires_recent_auth` impecável não protege
nada se o endpoint esquecer de chamá-la, e esse esquecimento não aparece em
nenhum teste de unidade.

# Sobre o que é substituído
Só a fronteira com o Firebase: quem é o chamador (no lugar de verificar um ID
token de verdade) e os clientes de banco e de armazenamento. O roteamento, a
validação do corpo, a ordem das verificações e os códigos de resposta são os de
produção.
"""

from __future__ import annotations

import os
import time

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

os.environ.setdefault("FIREBASE_PROJECT_ID", "demo-scorpions")
os.environ.setdefault(
    "FIREBASE_SERVICE_ACCOUNT",
    '{"type":"service_account","project_id":"demo-scorpions",'
    '"private_key":"nao-e-uma-chave","client_email":"teste@exemplo"}',
)

from app import account, quota  # noqa: E402
from app import main as main_mod  # noqa: E402
from app.auth import Caller, Role, current_caller  # noqa: E402
from app.main import app  # noqa: E402


def _caller(
    *,
    uid: str = "u1",
    role: Role = Role.USER,
    idade_do_login: int = 0,
    verificado: bool = True,
) -> Caller:
    return Caller(
        uid=uid,
        email="a@b.c",
        email_verified=verificado,
        role=role,
        auth_time=int(time.time()) - idade_do_login,
    )


@pytest.fixture
def cliente(monkeypatch):
    """Cliente HTTP contra o aplicativo real, sem subir o Firebase.

    `lifespan` inicializaria o Admin SDK com a credencial falsa e falharia;
    `TestClient` sem `with` não o dispara. O audit log é substituído por uma
    lista — o que interessa aqui é **se** foi chamado, e com o quê.
    """
    registros: list[dict] = []

    def gravar(settings, **campos):
        registros.append(campos)

    monkeypatch.setattr(main_mod, "record", gravar)
    monkeypatch.setattr(account, "record", gravar)

    c = TestClient(app, raise_server_exceptions=False)
    c.registros = registros  # type: ignore[attr-defined]
    yield c
    app.dependency_overrides.clear()


def _entrar_como(caller: Caller) -> None:
    app.dependency_overrides[current_caller] = lambda: caller


# =============================================================================
# Ninguém entra sem token
# =============================================================================


@pytest.mark.parametrize(
    ("metodo", "caminho"),
    [
        ("POST", "/v1/analyses"),
        ("GET", "/v1/me/quota"),
        ("GET", "/v1/me/data"),
        ("DELETE", "/v1/me"),
        ("GET", "/v1/review-queue"),
    ],
)
def test_sem_token_e_401(cliente, metodo: str, caminho: str) -> None:
    """Todo endpoint que toca dado de usuário exige autenticação.

    Parametrizado sobre a lista inteira, de propósito: um endpoint novo que
    esqueça `Depends(current_caller)` é o tipo de erro que uma revisão deixa
    passar. Quem adicionar um endpoint acrescenta uma linha aqui.
    """
    corpo = (
        {"sessionId": "abc12345", "views": [{"captureType": "top_view", "fileName": "processed.jpg"}]}
        if metodo == "POST"
        else None
    )
    r = cliente.request(metodo, caminho, json=corpo)

    assert r.status_code == 401
    assert r.headers.get("x-request-id"), "toda resposta leva o identificador"


def test_token_malformado_e_401(cliente) -> None:
    for cabecalho in ["", "Bearer", "Bearer ", "Basic abc", "token-solto"]:
        r = cliente.get("/v1/me/quota", headers={"Authorization": cabecalho})
        assert r.status_code == 401, f"aceitou: {cabecalho!r}"


def test_health_e_publico_e_nao_vaza_configuracao(cliente) -> None:
    """O único endpoint sem autenticação, e ele não diz nada além do estado."""
    r = cliente.get("/health")

    assert r.status_code == 200
    texto = r.text.lower()
    for proibido in ["private_key", "client_email", "service_account", "nao-e-uma-chave"]:
        assert proibido not in texto


def test_documentacao_interativa_esta_fora_do_ar(cliente) -> None:
    """Ela descreveria a superfície inteira da API para qualquer visitante."""
    for caminho in ["/docs", "/redoc", "/openapi.json"]:
        assert cliente.get(caminho).status_code == 404


# =============================================================================
# DELETE /v1/me — a reautenticação está LIGADA  (MEDIUM-5 + HIGH-2)
# =============================================================================


def test_excluir_conta_com_login_antigo_pede_senha(cliente, monkeypatch) -> None:
    """O teste que justifica este arquivo.

    `requires_recent_auth` tem os próprios testes. Este confirma que o endpoint
    **o chama** — e que, quando recusa, a cascata nem começa.
    """
    cascata_rodou = []
    monkeypatch.setattr(
        account, "delete_account", lambda s, c, r: cascata_rodou.append(1)
    )
    _entrar_como(_caller(idade_do_login=86_400))  # senha apresentada ontem

    r = cliente.delete("/v1/me")

    assert r.status_code == 401
    assert r.headers.get("x-reauth-required") == "true"
    assert cascata_rodou == [], "a cascata começou sem a senha ser confirmada"


def test_excluir_conta_com_login_recente_apaga(cliente, monkeypatch) -> None:
    relatorio = account.DeletionReport(images=3, identifications=2)
    monkeypatch.setattr(account, "delete_account", lambda s, c, r: relatorio)
    _entrar_como(_caller(idade_do_login=10))

    r = cliente.delete("/v1/me")

    assert r.status_code == 200
    corpo = r.json()
    assert corpo["deleted"] is True
    assert corpo["images"] == 3
    assert corpo["identifications"] == 2
    assert corpo["requestId"]


def test_o_recibo_de_exclusao_nao_traz_dado_pessoal(cliente, monkeypatch) -> None:
    """Contagens, e só.

    Dado pessoal numa resposta de exclusão seria o oposto do que a operação
    acabou de fazer.
    """
    monkeypatch.setattr(
        account,
        "delete_account",
        lambda s, c, r: account.DeletionReport(images=1, identifications=1),
    )
    _entrar_como(_caller(idade_do_login=10))

    r = cliente.delete("/v1/me")

    assert set(r.json()) == {"deleted", "images", "identifications", "requestId"}
    assert "a@b.c" not in r.text
    assert "users/" not in r.text


def test_o_uid_da_exclusao_vem_do_token(cliente, monkeypatch) -> None:
    """Não existe corpo, parâmetro nem cabeçalho que troque de quem é a conta.

    É o IDOR fechado por construção: `DELETE /v1/me` não aceita identificador
    nenhum, então não há o que adulterar.
    """
    visto = {}

    def capturar(settings, caller, rid):
        visto["uid"] = caller.uid
        return account.DeletionReport()

    monkeypatch.setattr(account, "delete_account", capturar)
    _entrar_como(_caller(uid="dono-real", idade_do_login=10))

    cliente.request(
        "DELETE",
        "/v1/me",
        params={"uid": "vitima", "userId": "vitima"},
        headers={"X-User-Id": "vitima"},
        json={"uid": "vitima", "userId": "vitima"},
    )

    assert visto["uid"] == "dono-real"


# =============================================================================
# POST /v1/analyses — a cota está LIGADA  (MEDIUM-4)
# =============================================================================

_PEDIDO = {
    "sessionId": "abc12345",
    "views": [{"captureType": "top_view", "fileName": "processed.jpg"}],
}


def test_analise_cobra_cota_antes_de_responder(cliente, monkeypatch) -> None:
    cobrancas: list[str] = []

    def cobrar(settings, uid, cost=1):
        cobrancas.append(uid)
        return quota.QuotaStatus(used=1, limit=60)

    monkeypatch.setattr(quota, "consume", cobrar)
    _entrar_como(_caller(uid="u7"))

    r = cliente.post("/v1/analyses", json=_PEDIDO)

    # 503 porque não há modelo — e isso é dito em voz alta, não devolvido como
    # resultado vazio.
    assert r.status_code == 503
    assert cobrancas == ["u7"], "a cota precisa ser cobrada, e do uid do token"


def test_analise_acima_da_cota_e_429_e_gera_auditoria(cliente, monkeypatch) -> None:
    def estourar(settings, uid, cost=1):
        raise HTTPException(
            status_code=429,
            detail="Você atingiu o limite de 60 análises por dia.",
            headers={"Retry-After": "3600"},
        )

    monkeypatch.setattr(quota, "consume", estourar)
    _entrar_como(_caller(uid="u8"))

    r = cliente.post("/v1/analyses", json=_PEDIDO)

    assert r.status_code == 429
    assert r.headers.get("retry-after") == "3600"

    # Bater no limite é o sinal mais barato de abuso que existe. Fica registrado.
    acoes = [reg["action"].value for reg in cliente.registros]
    assert "quota.exceeded" in acoes
    assert cliente.registros[0]["actor_uid"] == "u8"


def test_cota_indisponivel_recusa_a_analise(cliente, monkeypatch) -> None:
    """Falhar fechado, de ponta a ponta (§44)."""

    def indisponivel(settings, uid, cost=1):
        raise HTTPException(status_code=503, detail="Tente novamente.")

    monkeypatch.setattr(quota, "consume", indisponivel)
    _entrar_como(_caller())

    r = cliente.post("/v1/analyses", json=_PEDIDO)

    assert r.status_code == 503
    # E não gera registro de "cota excedida": não foi o usuário que excedeu.
    assert cliente.registros == []


def test_corpo_forjado_e_recusado_antes_de_cobrar_cota(cliente, monkeypatch) -> None:
    """A validação vem antes da cota.

    Na ordem inversa, mandar lixo consumiria a cota de quem errou o formato — e
    daria a um script um jeito de esgotar a própria cota sem fazer análise
    nenhuma, só para confundir as métricas.
    """
    cobrancas: list[str] = []
    monkeypatch.setattr(
        quota, "consume", lambda s, uid, cost=1: cobrancas.append(uid)
    )
    _entrar_como(_caller())

    r = cliente.post("/v1/analyses", json={**_PEDIDO, "confidence": 0.99})

    assert r.status_code == 422
    assert cobrancas == []


# =============================================================================
# GET /v1/me/quota e /v1/me/data
# =============================================================================


def test_ler_a_cota(cliente, monkeypatch) -> None:
    monkeypatch.setattr(
        quota, "peek", lambda s, uid: quota.QuotaStatus(used=12, limit=60)
    )
    _entrar_como(_caller())

    r = cliente.get("/v1/me/quota")

    assert r.status_code == 200
    assert r.json() == {"used": 12, "limit": 60, "remaining": 48}


def test_exportar_nao_exige_senha_recente(cliente, monkeypatch) -> None:
    """Ler o que a tela já mostra não pede senha.

    A assimetria com a exclusão é deliberada: exigir senha para leitura seria
    atrito sem ganho. O que pede senha é o irreversível.
    """
    monkeypatch.setattr(
        account, "export_data", lambda s, c, r: {"profile": {}, "identifications": []}
    )
    _entrar_como(_caller(idade_do_login=86_400))

    r = cliente.get("/v1/me/data")

    assert r.status_code == 200
    assert "identifications" in r.json()


# =============================================================================
# GET /v1/review-queue — papel conferido no servidor, e acesso registrado
# =============================================================================


def test_usuario_comum_nao_ve_a_fila(cliente) -> None:
    _entrar_como(_caller(role=Role.USER))

    r = cliente.get("/v1/review-queue")

    assert r.status_code == 403
    # A recusa não diz qual papel faltou.
    assert "admin" not in r.text.lower()
    assert "specialist" not in r.text.lower()
    # E quem foi barrado não gera registro de acesso — não acessou.
    assert cliente.registros == []


@pytest.mark.parametrize("papel", [Role.SPECIALIST, Role.REVIEWER, Role.ADMIN])
def test_acesso_privilegiado_a_fila_fica_registrado(cliente, papel) -> None:
    """Fecha o T-4 do modelo de ameaças antes de haver o que ler.

    Uma conta privilegiada comprometida leria dados de usuários sem deixar
    rastro. O registro nasce junto do endpoint, não depois.
    """
    _entrar_como(_caller(uid="revisor-1", role=papel))

    r = cliente.get("/v1/review-queue")

    assert r.status_code == 200
    assert len(cliente.registros) == 1
    assert cliente.registros[0]["action"].value == "review.queue_accessed"
    assert cliente.registros[0]["actor_uid"] == "revisor-1"


# =============================================================================
# Erros não vazam detalhe interno  (§17)
# =============================================================================


def test_erro_inesperado_devolve_frase_e_identificador(cliente, monkeypatch) -> None:
    def explodir(settings, uid):
        raise RuntimeError("PostgreSQL connection failed at 10.0.0.23: senha=hunter2")

    monkeypatch.setattr(quota, "peek", explodir)
    _entrar_como(_caller())

    r = cliente.get("/v1/me/quota")

    assert r.status_code == 500
    assert "10.0.0.23" not in r.text
    assert "hunter2" not in r.text
    assert "RuntimeError" not in r.text
    assert "Traceback" not in r.text
    assert r.json()["requestId"]
