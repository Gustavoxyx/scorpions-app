"""Testes do limite de uso por usuário.

Cobre o MEDIUM-4, que o modelo de ameaças marcava como a pior lacuna conhecida
(T-2 e T-8): um usuário com conta legítima podia gerar análises sem fim e
esgotar a cota do projeto.

`ImageLimits.maxIdentificationsPerDay = 60` existia desde a Fase 4 e o
comentário dizia em voz alta que **ninguém o aplicava**. Estes testes são o
"agora alguém aplica".
"""

from __future__ import annotations

import os

import pytest
from fastapi import HTTPException

os.environ.setdefault("FIREBASE_PROJECT_ID", "demo-scorpions")
os.environ.setdefault(
    "FIREBASE_SERVICE_ACCOUNT",
    '{"type":"service_account","project_id":"demo-scorpions",'
    '"private_key":"nao-e-uma-chave","client_email":"teste@exemplo"}',
)

from app import quota  # noqa: E402
from app.config import get_settings  # noqa: E402


# =============================================================================
# Dublê transacional
# =============================================================================


class DocFalso:
    def __init__(self, loja: dict, chave: str):
        self._loja = loja
        self._chave = chave

    @property
    def exists(self) -> bool:
        return self._chave in self._loja

    def to_dict(self) -> dict | None:
        return self._loja.get(self._chave)

    def get(self, transaction=None):
        del transaction
        return self


class RefFalsa:
    def __init__(self, loja: dict, chave: str):
        self._loja = loja
        self._chave = chave

    def get(self, transaction=None):
        del transaction
        return DocFalso(self._loja, self._chave)


class TransacaoFalsa:
    def __init__(self, loja: dict):
        self._loja = loja
        self.escritas = 0

    def set(self, ref, dados, merge=False):
        del merge
        self.escritas += 1
        atual = self._loja.setdefault(ref._chave, {})
        atual.update({k: v for k, v in dados.items() if k != "updatedAt"})


class ClienteFalso:
    def __init__(self, loja: dict):
        self._loja = loja
        self.transacoes: list[TransacaoFalsa] = []

    def transaction(self) -> TransacaoFalsa:
        t = TransacaoFalsa(self._loja)
        self.transacoes.append(t)
        return t


@pytest.fixture
def loja(monkeypatch):
    """Substitui o Firestore e o decorador transacional.

    `@firestore.transactional` embrulha a função para que o SDK a repita em caso
    de conflito. O dublê a chama direto, uma vez: o que está sob teste é a
    **decisão** de conceder ou recusar, não a mecânica de repetição do SDK — essa
    é código do Google e já é testada por ele.

    O que o dublê **preserva** é que a decisão e a escrita acontecem no mesmo
    bloco. É isso que impede dois pedidos simultâneos de passarem de 60.
    """
    dados: dict[str, dict] = {}
    cliente = ClienteFalso(dados)

    def ref_falsa(settings, uid):
        return RefFalsa(dados, f"users/{uid}/quotas/hoje")

    monkeypatch.setattr(quota, "_doc_ref", ref_falsa)

    import app.clients as clients

    monkeypatch.setattr(clients, "firestore_client", lambda s: cliente)

    # O decorador real precisa de um cliente de verdade para funcionar.
    from google.cloud import firestore

    monkeypatch.setattr(firestore, "transactional", lambda fn: fn)

    return dados, cliente


# =============================================================================
# Consumo
# =============================================================================


def test_primeiro_uso_do_dia_e_concedido(loja) -> None:
    dados, _ = loja

    estado = quota.consume(get_settings(), "u1")

    assert estado.used == 1
    assert estado.limit == 60
    assert estado.remaining == 59
    assert not estado.exceeded


def test_consumo_acumula(loja) -> None:
    dados, _ = loja

    for esperado in range(1, 6):
        assert quota.consume(get_settings(), "u1").used == esperado


def test_no_limite_exato_ainda_passa(loja) -> None:
    """60 análises são permitidas; a 61ª não.

    O limite é inclusivo. Recusar a 60ª faria o número anunciado ao usuário
    mentir por um.
    """
    dados, _ = loja
    dados["users/u1/quotas/hoje"] = {"count": 59}

    estado = quota.consume(get_settings(), "u1")

    assert estado.used == 60
    assert estado.remaining == 0


def test_acima_do_limite_e_recusado_com_429(loja) -> None:
    dados, _ = loja
    dados["users/u1/quotas/hoje"] = {"count": 60}

    with pytest.raises(HTTPException) as erro:
        quota.consume(get_settings(), "u1")

    assert erro.value.status_code == 429
    assert "60" in erro.value.detail


def test_a_recusa_nao_incrementa_o_contador(loja) -> None:
    """Senão cada tentativa recusada empurraria o contador para cima.

    O efeito prático seria uma punição crescente: quem bate no limite e insiste
    acabaria com um número que não corresponde a análise nenhuma, e o registro
    deixaria de medir uso.
    """
    dados, cliente = loja
    dados["users/u1/quotas/hoje"] = {"count": 60}

    for _ in range(5):
        with pytest.raises(HTTPException):
            quota.consume(get_settings(), "u1")

    assert dados["users/u1/quotas/hoje"]["count"] == 60
    assert all(t.escritas == 0 for t in cliente.transacoes)


def test_retry_after_aponta_para_a_virada_do_dia(loja) -> None:
    """Um número honesto, não um valor fixo.

    Um cliente que respeita o cabeçalho volta na hora certa, em vez de bater de
    novo em 60 segundos e levar outro 429.
    """
    dados, _ = loja
    dados["users/u1/quotas/hoje"] = {"count": 60}

    with pytest.raises(HTTPException) as erro:
        quota.consume(get_settings(), "u1")

    segundos = int(erro.value.headers["Retry-After"])
    assert 60 <= segundos <= 86_400


def test_custo_maior_que_um_e_respeitado(loja) -> None:
    """Uma análise de duas fotos pode valer mais que uma unidade.

    O parâmetro existe para que isso seja decidido na borda, e não dentro do
    contador.
    """
    dados, _ = loja
    dados["users/u1/quotas/hoje"] = {"count": 58}

    estado = quota.consume(get_settings(), "u1", cost=2)
    assert estado.used == 60

    with pytest.raises(HTTPException):
        quota.consume(get_settings(), "u1", cost=1)


def test_custo_que_estoura_e_recusado_inteiro(loja) -> None:
    """Não consome parcialmente.

    Conceder 1 de 2 deixaria o chamador achando que pode fazer as duas
    análises — e a segunda falharia no meio do trabalho.
    """
    dados, _ = loja
    dados["users/u1/quotas/hoje"] = {"count": 59}

    with pytest.raises(HTTPException) as erro:
        quota.consume(get_settings(), "u1", cost=2)

    assert erro.value.status_code == 429
    assert dados["users/u1/quotas/hoje"]["count"] == 59


def test_cada_usuario_tem_a_propria_cota(loja) -> None:
    dados, _ = loja
    dados["users/u1/quotas/hoje"] = {"count": 60}

    # u1 está no limite; u2 não deve ser afetado.
    assert quota.consume(get_settings(), "u2").used == 1

    with pytest.raises(HTTPException):
        quota.consume(get_settings(), "u1")


# =============================================================================
# Falhar fechado
# =============================================================================


def test_falha_do_firestore_recusa_a_operacao(loja, monkeypatch) -> None:
    """§44: em caso de dúvida, negar.

    A alternativa — liberar quando o Firestore oscila — é um atacante esperando
    pela oscilação.
    """
    dados, cliente = loja

    def explode():
        raise RuntimeError("firestore indisponível")

    monkeypatch.setattr(cliente, "transaction", explode)

    with pytest.raises(HTTPException) as erro:
        quota.consume(get_settings(), "u1")

    assert erro.value.status_code == 503
    # A mensagem não entrega detalhe de infraestrutura (§17).
    assert "firestore" not in erro.value.detail.lower()
    assert "indisponível" not in erro.value.detail.lower()


# =============================================================================
# Leitura informativa
# =============================================================================


def test_peek_nao_altera_nada(loja) -> None:
    dados, cliente = loja
    dados["users/u1/quotas/hoje"] = {"count": 7}

    estado = quota.peek(get_settings(), "u1")

    assert estado.used == 7
    assert estado.remaining == 53
    assert dados["users/u1/quotas/hoje"]["count"] == 7
    assert cliente.transacoes == []


def test_peek_de_quem_nao_usou_nada(loja) -> None:
    estado = quota.peek(get_settings(), "novo")
    assert estado.used == 0
    assert estado.remaining == 60


def test_peek_falha_aberto_e_consume_falha_fechado(loja, monkeypatch) -> None:
    """As duas funções falham para lados **opostos**, de propósito.

    `peek` só informa: mostrar "restam 60" quando o contador está indisponível é
    impreciso, mas recusar a tela por isso seria pior. `consume` autoriza:
    liberar na dúvida seria o buraco.

    Este teste existe porque a assimetria parece um descuido para quem lê rápido.
    """
    def ref_que_explode(settings, uid):
        raise RuntimeError("indisponível")

    monkeypatch.setattr(quota, "_doc_ref", ref_que_explode)

    # peek: segue em frente.
    assert quota.peek(get_settings(), "u1").used == 0

    # consume: recusa.
    with pytest.raises(HTTPException) as erro:
        quota.consume(get_settings(), "u1")
    assert erro.value.status_code == 503


# =============================================================================
# A chave do dia
# =============================================================================


def test_a_chave_do_dia_e_utc(monkeypatch) -> None:
    """UTC, e não o fuso do usuário.

    O fuso vem do cliente, e o cliente não é confiável: alguém que escolhesse o
    fuso teria um "novo dia" a cada troca, e com ele uma cota nova.
    """
    chave = quota._hoje_utc()

    assert len(chave) == 10
    assert chave.count("-") == 2

    from datetime import datetime, timezone

    assert chave == datetime.now(timezone.utc).strftime("%Y-%m-%d")


def test_quota_status_nao_devolve_restante_negativo() -> None:
    """Se o contador for parar acima do limite — limite reduzido por
    configuração, por exemplo —, "restam -5" não é algo que se mostre numa tela.
    """
    estado = quota.QuotaStatus(used=70, limit=60)

    assert estado.remaining == 0
    assert estado.exceeded
