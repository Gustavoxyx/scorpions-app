"""Testes do que a Fase 0 acrescentou ao serviço.

Limite de chamadas, App Check, papel carregado sob demanda, segundo fator, e a
validação das imagens no caminho da análise. Cada grupo testa a peça e, em
seguida, que ela está **ligada** ao endpoint — uma proteção correta que nenhum
endpoint chama não protege nada.
"""

from __future__ import annotations

import asyncio
import io
import os
import time
from dataclasses import replace

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from PIL import Image
from pydantic import ValidationError

from app import analysis, appcheck, auth, images, quota, ratelimit
from app import main as main_mod
from app.auth import Caller, Role, current_caller, current_staff
from app.config import get_settings
from app.main import app
from app.schemas import AnalysisRequest, AnalysisResponse


def _caller(**campos) -> Caller:
    base = dict(
        uid="u1",
        email="a@b.c",
        email_verified=True,
        role=Role.USER,
        auth_time=int(time.time()),
    )
    base.update(campos)
    return Caller(**base)


@pytest.fixture
def cliente(monkeypatch):
    monkeypatch.setattr(main_mod, "record", lambda settings, **campos: None)
    c = TestClient(app, raise_server_exceptions=False)
    yield c
    app.dependency_overrides.clear()


def _entrar_como(caller: Caller) -> None:
    app.dependency_overrides[current_caller] = lambda: caller
    app.dependency_overrides[current_staff] = lambda: caller


def _com_settings(**mudancas) -> None:
    ajustado = replace(get_settings(), **mudancas)
    app.dependency_overrides[get_settings] = lambda: ajustado


_PEDIDO = {
    "sessionId": "abc12345",
    "views": [{"captureType": "top_view", "fileName": "processed.jpg"}],
}


# =============================================================================
# Limite de chamadas
# =============================================================================


def test_janela_deixa_passar_ate_o_limite_e_recusa_o_seguinte() -> None:
    janela = ratelimit.SlidingWindow(3, 60)

    assert [janela.hit("k", now=t) for t in (0.0, 1.0, 2.0)] == [None, None, None]
    espera = janela.hit("k", now=3.0)

    assert espera is not None
    assert espera == pytest.approx(57.0), "libera quando a primeira chamada sai"


def test_janela_libera_quando_as_chamadas_antigas_saem() -> None:
    janela = ratelimit.SlidingWindow(2, 10)
    janela.hit("k", now=0.0)
    janela.hit("k", now=1.0)

    assert janela.hit("k", now=5.0) is not None
    assert janela.hit("k", now=10.5) is None


def test_chamada_recusada_nao_empurra_a_liberacao() -> None:
    """Insistir não pode prolongar o bloqueio — nem encurtá-lo."""
    janela = ratelimit.SlidingWindow(1, 10)
    janela.hit("k", now=0.0)

    for t in (1.0, 2.0, 3.0, 9.0):
        assert janela.hit("k", now=t) is not None
    assert janela.hit("k", now=10.1) is None


def test_chaves_sao_independentes() -> None:
    janela = ratelimit.SlidingWindow(1, 60)
    assert janela.hit("a", now=0.0) is None
    assert janela.hit("b", now=0.0) is None
    assert janela.hit("a", now=1.0) is not None


def test_janela_nao_cresce_sem_teto() -> None:
    """Um endereço novo por chamada não pode ocupar memória para sempre."""
    janela = ratelimit.SlidingWindow(5, 60, max_keys=100)
    for i in range(1000):
        janela.hit(f"endereco-{i}", now=float(i))

    assert len(janela._hits) <= 100


def test_endpoint_de_conta_recusa_a_rajada(cliente, monkeypatch) -> None:
    monkeypatch.setattr(
        quota, "peek", lambda settings, uid: quota.QuotaStatus(used=0, limit=60)
    )
    _entrar_como(_caller())

    respostas = [cliente.get("/v1/me/quota").status_code for _ in range(31)]

    assert respostas[:30] == [200] * 30
    assert respostas[30] == 429


def test_recusa_por_limite_diz_quando_voltar(cliente, monkeypatch) -> None:
    monkeypatch.setattr(
        quota, "peek", lambda settings, uid: quota.QuotaStatus(used=0, limit=60)
    )
    _entrar_como(_caller())
    for _ in range(30):
        cliente.get("/v1/me/quota")

    r = cliente.get("/v1/me/quota")

    assert r.status_code == 429
    assert int(r.headers["retry-after"]) >= 1


def test_o_limite_e_por_conta(cliente, monkeypatch) -> None:
    monkeypatch.setattr(
        quota, "peek", lambda settings, uid: quota.QuotaStatus(used=0, limit=60)
    )
    _entrar_como(_caller(uid="u1"))
    for _ in range(30):
        cliente.get("/v1/me/quota")
    assert cliente.get("/v1/me/quota").status_code == 429

    _entrar_como(_caller(uid="u2"))
    assert cliente.get("/v1/me/quota").status_code == 200


def test_janela_por_endereco_barra_antes_da_autenticacao_quando_ligada(
    cliente,
) -> None:
    """Ligada, ela roda antes de o token ser verificado."""
    _com_settings(rate_limit_by_ip=True)

    respostas = [cliente.get("/v1/me/quota").status_code for _ in range(121)]

    assert respostas[:120] == [401] * 120
    assert respostas[120] == 429


def test_janela_por_endereco_nasce_desligada(cliente) -> None:
    """Atrás de um proxy todos os clientes têm o mesmo endereço.

    Com a janela ligada ali, uma pessoa em laço esgotaria o limite de todo
    mundo: a proteção viraria negação de serviço. O padrão precisa ser o que
    não derruba ninguém.
    """
    respostas = {cliente.get("/v1/me/quota").status_code for _ in range(200)}

    assert respostas == {401}


def test_health_fica_fora_do_limite(cliente) -> None:
    """Quem consulta o `/health` é o provedor, de minuto em minuto, para sempre."""
    assert {cliente.get("/health").status_code for _ in range(150)} == {200}


# =============================================================================
# App Check
# =============================================================================


def test_app_check_desligado_nao_recusa_ninguem(cliente, monkeypatch) -> None:
    monkeypatch.setattr(
        quota, "peek", lambda settings, uid: quota.QuotaStatus(used=0, limit=60)
    )
    _entrar_como(_caller())

    assert cliente.get("/v1/me/quota").status_code == 200


def test_app_check_ligado_recusa_pedido_sem_token(cliente, monkeypatch) -> None:
    _com_settings(require_app_check=True)
    _entrar_como(_caller())

    r = cliente.get("/v1/me/quota")

    assert r.status_code == 401
    assert "Aplicativo" in r.json()["detail"]


def test_app_check_ligado_recusa_token_que_nao_confere(cliente, monkeypatch) -> None:
    def falha(token, app=None):
        raise ValueError("detalhe interno do SDK que não pode chegar ao cliente")

    monkeypatch.setattr(appcheck.fb_app_check, "verify_token", falha)
    monkeypatch.setattr(appcheck, "firebase_app", lambda settings: object())
    _com_settings(require_app_check=True)
    _entrar_como(_caller())

    r = cliente.get("/v1/me/quota", headers={"X-Firebase-AppCheck": "forjado"})

    assert r.status_code == 401
    assert "SDK" not in r.text


def test_app_check_ligado_aceita_token_valido(cliente, monkeypatch) -> None:
    vistos: list[str] = []
    monkeypatch.setattr(
        appcheck.fb_app_check,
        "verify_token",
        lambda token, app=None: vistos.append(token) or {"sub": "app"},
    )
    monkeypatch.setattr(appcheck, "firebase_app", lambda settings: object())
    monkeypatch.setattr(
        quota, "peek", lambda settings, uid: quota.QuotaStatus(used=0, limit=60)
    )
    _com_settings(require_app_check=True)
    _entrar_como(_caller())

    r = cliente.get("/v1/me/quota", headers={"X-Firebase-AppCheck": "bom"})

    assert r.status_code == 200
    assert vistos == ["bom"]


# =============================================================================
# Papel sob demanda, e segundo fator
# =============================================================================


def _token(monkeypatch, claims: dict) -> None:
    monkeypatch.setattr(auth, "firebase_app", lambda settings: object())
    monkeypatch.setattr(
        auth.fb_auth, "verify_id_token", lambda token, app=None, check_revoked=False: claims
    )


def test_autenticar_nao_le_o_firestore(monkeypatch) -> None:
    """A maioria dos endpoints só precisa saber QUEM chama."""
    from app import clients

    def proibido(settings):
        raise AssertionError("current_caller não deveria ler o Firestore")

    monkeypatch.setattr(clients, "firestore_client", proibido)
    _token(monkeypatch, {"uid": "u1", "email": "a@b.c", "email_verified": True})

    caller = asyncio.run(
        auth.current_caller(authorization="Bearer x", settings=get_settings())
    )

    assert caller.uid == "u1"
    assert caller.role is None


def test_papel_nao_carregado_nao_autoriza_nada() -> None:
    """`None` é "não consultado", e precisa falhar fechado."""
    sem_papel = Caller(uid="u1", email=None, email_verified=True)

    with pytest.raises(HTTPException) as erro:
        sem_papel.requires(Role.USER, Role.ADMIN)
    assert erro.value.status_code == 403


class _Perfil:
    def __init__(self, dados):
        self._dados = dados
        self.exists = dados is not None

    def to_dict(self):
        return self._dados


class _Banco:
    def __init__(self, dados):
        self._dados = dados

    def collection(self, nome):
        return self

    def document(self, uid):
        return self

    def get(self):
        return _Perfil(self._dados)


@pytest.mark.parametrize(
    ("documento", "esperado"),
    [
        ({"role": "admin"}, Role.ADMIN),
        ({"role": "reviewer"}, Role.REVIEWER),
        ({"role": "inventado"}, Role.USER),
        ({}, Role.USER),
        (None, Role.USER),
    ],
)
def test_o_papel_vem_do_documento_e_falha_para_o_menor(
    monkeypatch, documento, esperado
) -> None:
    from app import clients

    monkeypatch.setattr(clients, "firestore_client", lambda s: _Banco(documento))

    equipe = asyncio.run(
        auth.current_staff(
            caller=Caller(uid="u1", email=None, email_verified=True),
            settings=get_settings(),
        )
    )

    assert equipe.role is esperado


def test_segundo_fator_vem_da_claim_do_token(monkeypatch) -> None:
    _token(
        monkeypatch,
        {"uid": "u1", "firebase": {"sign_in_second_factor": "totp"}},
    )

    caller = asyncio.run(
        auth.current_caller(authorization="Bearer x", settings=get_settings())
    )

    assert caller.second_factor == "totp"


def test_fila_de_revisao_exige_segundo_fator_quando_ligado(cliente) -> None:
    _com_settings(require_mfa_for_staff=True)

    _entrar_como(_caller(role=Role.ADMIN))
    assert cliente.get("/v1/review-queue").status_code == 403

    _entrar_como(_caller(role=Role.ADMIN, second_factor="totp"))
    assert cliente.get("/v1/review-queue").status_code == 200


def test_fila_de_revisao_sem_a_exigencia_continua_como_era(cliente) -> None:
    _entrar_como(_caller(role=Role.ADMIN))
    assert cliente.get("/v1/review-queue").status_code == 200


# =============================================================================
# Imagens no caminho da análise
# =============================================================================


def _jpeg(largura: int = 640, altura: int = 480) -> bytes:
    """Um JPEG de verdade, com ruído para passar do tamanho mínimo."""
    imagem = Image.frombytes("RGB", (largura, altura), os.urandom(largura * altura * 3))
    saida = io.BytesIO()
    imagem.save(saida, format="JPEG", quality=85)
    return saida.getvalue()


class _Blob:
    def __init__(self, dados: bytes, content_type: str = "image/jpeg", size=None):
        self._dados = dados
        self.content_type = content_type
        self.size = len(dados) if size is None else size
        self.baixado = False

    def download_as_bytes(self) -> bytes:
        self.baixado = True
        return self._dados


class _Bucket:
    def __init__(self, arquivos: dict[str, _Blob]):
        self.arquivos = arquivos
        self.pedidos: list[str] = []

    def get_blob(self, caminho: str):
        self.pedidos.append(caminho)
        return self.arquivos.get(caminho)


def _com_bucket(monkeypatch, arquivos: dict[str, _Blob]) -> _Bucket:
    bucket = _Bucket(arquivos)
    monkeypatch.setattr(analysis, "storage_bucket", lambda settings: bucket)
    return bucket


_COM_STORAGE = replace(get_settings(), storage_bucket="bucket-de-teste")
_CAMINHO = "users/u1/identifications/abc12345/processed.jpg"


def test_sem_bucket_configurado_nada_e_conferido() -> None:
    """O Storage de produção não existe. A função diz isso devolvendo vazio."""
    vistas = analysis.load_views(
        get_settings(), "u1", AnalysisRequest.model_validate(_PEDIDO)
    )
    assert vistas == []


def test_imagem_valida_e_carregada_e_conferida(monkeypatch) -> None:
    bucket = _com_bucket(monkeypatch, {_CAMINHO: _Blob(_jpeg())})

    vistas = analysis.load_views(
        _COM_STORAGE, "u1", AnalysisRequest.model_validate(_PEDIDO)
    )

    assert len(vistas) == 1
    assert vistas[0].check.ok
    assert vistas[0].check.detected is images.ImageFormat.JPEG
    assert (vistas[0].check.width, vistas[0].check.height) == (640, 480)
    assert bucket.pedidos == [_CAMINHO]


def test_o_caminho_usa_o_uid_do_token_e_nao_alcanca_outra_pessoa(monkeypatch) -> None:
    """A imagem existe, mas na pasta de outra conta."""
    _com_bucket(
        monkeypatch,
        {"users/vitima/identifications/abc12345/processed.jpg": _Blob(_jpeg())},
    )

    with pytest.raises(HTTPException) as erro:
        analysis.load_views(
            _COM_STORAGE, "u1", AnalysisRequest.model_validate(_PEDIDO)
        )
    assert erro.value.status_code == 404


def test_arquivo_grande_demais_e_recusado_sem_ser_baixado(monkeypatch) -> None:
    gigante = _Blob(b"", size=500 * 1024 * 1024)
    _com_bucket(monkeypatch, {_CAMINHO: gigante})

    with pytest.raises(HTTPException) as erro:
        analysis.load_views(
            _COM_STORAGE, "u1", AnalysisRequest.model_validate(_PEDIDO)
        )

    assert erro.value.status_code == 422
    assert erro.value.headers["X-Image-Rejection"] == "too_large"
    assert not gigante.baixado, "baixar para depois recusar gastaria a memória"


def test_arquivo_que_nao_e_imagem_e_recusado(monkeypatch) -> None:
    """Com nome e tipo declarado de imagem, e conteúdo de outra coisa."""
    executavel = b"MZ" + os.urandom(64 * 1024)
    _com_bucket(monkeypatch, {_CAMINHO: _Blob(executavel, "image/jpeg")})

    with pytest.raises(HTTPException) as erro:
        analysis.load_views(
            _COM_STORAGE, "u1", AnalysisRequest.model_validate(_PEDIDO)
        )
    assert erro.value.status_code == 422


def test_falha_do_storage_vira_503_sem_detalhe(monkeypatch) -> None:
    def quebra(settings):
        raise RuntimeError("bucket gs://nome-interno inacessível")

    monkeypatch.setattr(analysis, "storage_bucket", quebra)

    with pytest.raises(HTTPException) as erro:
        analysis.load_views(
            _COM_STORAGE, "u1", AnalysisRequest.model_validate(_PEDIDO)
        )
    assert erro.value.status_code == 503
    assert "gs://" not in erro.value.detail


def test_a_analise_confere_a_imagem_antes_de_responder(cliente, monkeypatch) -> None:
    """A peça está ligada: o endpoint recusa a imagem ruim."""
    monkeypatch.setattr(
        quota, "consume", lambda settings, uid, cost=1: quota.QuotaStatus(used=1, limit=60)
    )
    _com_bucket(monkeypatch, {_CAMINHO: _Blob(b"MZ" + os.urandom(64 * 1024))})
    app.dependency_overrides[get_settings] = lambda: _COM_STORAGE
    _entrar_como(_caller())

    r = cliente.post("/v1/analyses", json=_PEDIDO)

    assert r.status_code == 422
    assert r.headers["x-image-rejection"]


def test_com_imagem_boa_a_analise_segue_ate_a_falta_de_modelo(cliente, monkeypatch) -> None:
    monkeypatch.setattr(
        quota, "consume", lambda settings, uid, cost=1: quota.QuotaStatus(used=1, limit=60)
    )
    _com_bucket(monkeypatch, {_CAMINHO: _Blob(_jpeg())})
    app.dependency_overrides[get_settings] = lambda: _COM_STORAGE
    _entrar_como(_caller())

    r = cliente.post("/v1/analyses", json=_PEDIDO)

    assert r.status_code == 503
    assert "ainda não está disponível" in r.json()["detail"]


def test_analise_exige_email_confirmado_e_nao_cobra_cota(cliente, monkeypatch) -> None:
    cobradas: list[str] = []
    monkeypatch.setattr(
        quota,
        "consume",
        lambda settings, uid, cost=1: cobradas.append(uid)
        or quota.QuotaStatus(used=1, limit=60),
    )
    _entrar_como(_caller(email_verified=False))

    r = cliente.post("/v1/analyses", json=_PEDIDO)

    assert r.status_code == 403
    assert cobradas == [], "recusar por e-mail não pode gastar a cota de ninguém"


def test_nao_existe_analisador_enquanto_nao_houver_modelo(cliente) -> None:
    assert analysis.get_analyzer() is None
    assert cliente.get("/health").json()["modelAvailable"] is False


# =============================================================================
# O contrato da resposta de análise
# =============================================================================

_RESPOSTA_COMPLETA = {
    "sessionId": "abc12345",
    "requestId": "r-1",
    "status": "identified",
    "species": {
        "speciesId": "tityus-serrulatus",
        "scientificName": "Tityus serrulatus",
        "confidence": 0.82,
    },
    "alternatives": [
        {
            "speciesId": "tityus-bahiensis",
            "scientificName": "Tityus bahiensis",
            "confidence": 0.11,
        }
    ],
    "modelVersion": "exemplo-de-forma",
    "fusion": {
        "viewCount": 2,
        "agreeOnTop1": True,
        "agreement": 0.77,
        "decisionLevel": "high_confidence",
        "reasons": [],
        "thresholdsCalibrated": False,
    },
    "needsHumanReview": False,
}


def test_o_contrato_comporta_um_resultado_completo() -> None:
    resposta = AnalysisResponse.model_validate(_RESPOSTA_COMPLETA)

    assert resposta.species is not None
    assert resposta.fusion is not None and resposta.fusion.viewCount == 2


def test_o_contrato_comporta_um_modelo_conjunto_sem_medida_de_acordo() -> None:
    """Um modelo de duas entradas não tem "acordo entre vistas" para informar."""
    conjunto = {**_RESPOSTA_COMPLETA, "fusion": {
        "viewCount": 2, "decisionLevel": "high_confidence",
        "thresholdsCalibrated": False,
    }}
    assert AnalysisResponse.model_validate(conjunto).fusion.agreement is None


def test_o_contrato_comporta_rejeicao_e_revisao_humana() -> None:
    rejeitada = AnalysisResponse.model_validate({
        "sessionId": "abc12345", "requestId": "r-2", "status": "rejected",
        "rejectionReason": "ambiguous", "needsHumanReview": True,
    })
    assert rejeitada.species is None and rejeitada.needsHumanReview


@pytest.mark.parametrize(
    "mudanca",
    [
        {"status": "aprovado"},
        {"species": {"speciesId": "x", "scientificName": "X", "confidence": 1.5}},
        {"species": {"speciesId": "x", "scientificName": "X", "confidence": -0.1}},
    ],
)
def test_o_contrato_recusa_valor_fora_do_previsto(mudanca) -> None:
    with pytest.raises(ValidationError):
        AnalysisResponse.model_validate({**_RESPOSTA_COMPLETA, **mudanca})


# =============================================================================
# Exclusão de conta
# =============================================================================


def test_a_cascata_de_exclusao_alcanca_o_contador_de_criacao() -> None:
    """`usage` nasceu com o limite de criação; a exclusão precisa levá-lo."""
    from app import account

    assert {"quotas", "usage"} <= set(account._SUBCOLECOES)
