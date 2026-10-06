"""Testes de segurança da API.

Cada caso aqui é uma tentativa de ataque descrita no briefing de segurança
(§30) ou um achado da auditoria. Todos precisam ser bloqueados.

Nenhum deles depende de Firebase real: o que está sendo testado é a camada de
validação e autorização do serviço, que roda antes de qualquer ida à rede.
"""

from __future__ import annotations

import os

import pytest
from pydantic import ValidationError

# A configuração precisa existir antes de importar qualquer coisa que a leia.
os.environ.setdefault("FIREBASE_PROJECT_ID", "demo-scorpions")
os.environ.setdefault(
    "FIREBASE_SERVICE_ACCOUNT",
    '{"type":"service_account","project_id":"demo-scorpions",'
    '"private_key":"nao-e-uma-chave","client_email":"teste@exemplo"}',
)

from app.auth import Role  # noqa: E402
from app.config import ConfigError, get_settings  # noqa: E402
from app.schemas import AnalysisRequest, ViewRef  # noqa: E402


# =============================================================================
# Mass assignment  (§10, §24 — "NÃO aceitar {role: admin} do cliente")
# =============================================================================


def test_corpo_com_confidence_e_recusado() -> None:
    """O achado HIGH-1, fechado na forma dos dados.

    `extra: forbid` faz o corpo ser **recusado**, não ter o campo ignorado em
    silêncio. Recusar é melhor: quem tentou descobre que tentou algo que não
    existe, e não fica com a impressão de que funcionou.
    """
    with pytest.raises(ValidationError):
        AnalysisRequest(
            sessionId="abc12345",
            views=[{"captureType": "top_view", "fileName": "processed.jpg"}],
            confidence=0.99,
        )


def test_corpo_com_role_admin_e_recusado() -> None:
    with pytest.raises(ValidationError):
        AnalysisRequest(
            sessionId="abc12345",
            views=[{"captureType": "top_view", "fileName": "processed.jpg"}],
            role="admin",
        )


def test_corpo_com_userid_e_recusado() -> None:
    """O dono sai do token, nunca do corpo (§20 da Fase 4, §35 da segurança)."""
    with pytest.raises(ValidationError):
        AnalysisRequest(
            sessionId="abc12345",
            views=[{"captureType": "top_view", "fileName": "processed.jpg"}],
            userId="uid-de-outra-pessoa",
        )


def test_corpo_com_species_e_recusado() -> None:
    with pytest.raises(ValidationError):
        AnalysisRequest(
            sessionId="abc12345",
            views=[{"captureType": "top_view", "fileName": "processed.jpg"}],
            speciesId="tityus-serrulatus",
        )


# =============================================================================
# Travessia de caminho e nomes de arquivo
# =============================================================================


@pytest.mark.parametrize(
    "nome",
    [
        "../../../etc/passwd",
        "../outro-usuario/original.jpg",
        "original.jpg/../../x",
        "shell.sh",
        "payload.exe",
        "original.svg",  # SVG carrega script
        "original.jpg.exe",
        "",
    ],
)
def test_nome_de_arquivo_fora_da_lista_e_recusado(nome: str) -> None:
    with pytest.raises(ValidationError):
        ViewRef(captureType="top_view", fileName=nome)


@pytest.mark.parametrize(
    "nome", ["original.jpg", "processed.jpg", "thumbnail.webp", "processed.png"]
)
def test_nomes_que_o_pipeline_gera_sao_aceitos(nome: str) -> None:
    assert ViewRef(captureType="top_view", fileName=nome).fileName == nome


@pytest.mark.parametrize(
    "nome", ["original-2.jpg", "processed-2.jpg", "thumbnail-2.webp"]
)
def test_nomes_da_segunda_vista_sao_aceitos(nome: str) -> None:
    """A segunda fotografia mora na mesma pasta, com sufixo `-2` (Fase 5).

    São exatamente os nomes que o aplicativo gera
    (`FirebaseImageUploadService.suffixFor`) e que a regra do Storage aceita. As
    três listas precisam concordar; esta é a do servidor.
    """
    assert ViewRef(captureType="tail", fileName=nome).fileName == nome


@pytest.mark.parametrize(
    "nome",
    [
        "original-3.jpg",  # não existe terceira vista
        "original-22.jpg",
        "original-0.jpg",
        "original-1.jpg",  # a primeira não leva sufixo
        "original--2.jpg",
        "original-2-2.jpg",
        "original-2.jpg.exe",
        "original-2",
        "-2.jpg",
        "original-2.jpeg",  # o pipeline não gera esta extensão
    ],
)
def test_so_existe_a_segunda_vista(nome: str) -> None:
    """Só `-2`, e não um padrão aberto.

    O pedido tem teto de duas vistas. Aceitar `-3` aqui seria aceitar um nome
    para o qual não há fotografia — e a regra do Storage o recusa pelo mesmo
    motivo: um padrão aberto deixaria guardar arquivos sem registro que os
    referencie.
    """
    with pytest.raises(ValidationError):
        ViewRef(captureType="tail", fileName=nome)


@pytest.mark.parametrize(
    "sid",
    [
        "../outro",
        "AbC12345",  # maiúscula não é gerada pelo nosso gerador de id
        "ab",  # curto demais
        "a" * 65,  # longo demais
        "abc 12345",
        "abc-12345",
        "'; DROP TABLE--",
    ],
)
def test_session_id_malformado_e_recusado(sid: str) -> None:
    with pytest.raises(ValidationError):
        AnalysisRequest(
            sessionId=sid,
            views=[{"captureType": "top_view", "fileName": "processed.jpg"}],
        )


def test_tipo_de_captura_desconhecido_e_recusado() -> None:
    with pytest.raises(ValidationError):
        ViewRef(captureType="qualquer_coisa", fileName="processed.jpg")


# =============================================================================
# Consumo de recursos  (§12, OWASP API4:2023)
# =============================================================================


def test_mais_de_duas_vistas_e_recusado() -> None:
    """Teto no número de imagens por análise.

    Sem ele, um pedido com mil vistas viraria mil inferências — o §12 chama
    isso de abuso da IA, e é o caminho mais barato para estourar a cota.
    """
    with pytest.raises(ValidationError):
        AnalysisRequest(
            sessionId="abc12345",
            views=[
                {"captureType": "top_view", "fileName": "processed.jpg"}
                for _ in range(3)
            ],
        )


def test_nenhuma_vista_e_recusado() -> None:
    with pytest.raises(ValidationError):
        AnalysisRequest(sessionId="abc12345", views=[])


# =============================================================================
# Papéis  (§4 — RBAC)
# =============================================================================


def test_papel_desconhecido_vira_user_e_nao_admin() -> None:
    """Falhar para o menor privilégio.

    Um campo `role` corrompido, ausente ou adulterado no documento não pode
    virar promoção. É o oposto do padrão "em caso de dúvida, libere".
    """
    for entrada in [None, "", "superadmin", "ADMIN", "root", "admin ", "0"]:
        assert Role.parse(entrada) is Role.USER, f"entrada: {entrada!r}"


def test_papeis_validos_sao_reconhecidos() -> None:
    assert Role.parse("admin") is Role.ADMIN
    assert Role.parse("specialist") is Role.SPECIALIST
    assert Role.parse("reviewer") is Role.REVIEWER
    assert Role.parse("user") is Role.USER


def test_requires_bloqueia_papel_insuficiente() -> None:
    from fastapi import HTTPException

    from app.auth import Caller

    comum = Caller(uid="u1", email="a@b.c", email_verified=True, role=Role.USER)

    with pytest.raises(HTTPException) as erro:
        comum.requires(Role.SPECIALIST, Role.REVIEWER, Role.ADMIN)
    assert erro.value.status_code == 403

    # A mensagem não diz se o recurso existe nem qual papel faltou: isso
    # entregaria a estrutura interna a quem está sondando.
    assert "não disponível" in erro.value.detail.lower()
    assert "admin" not in erro.value.detail.lower()


def test_requires_libera_papel_suficiente() -> None:
    from app.auth import Caller

    especialista = Caller(
        uid="u2", email="e@b.c", email_verified=True, role=Role.SPECIALIST
    )
    # Não levanta.
    especialista.requires(Role.SPECIALIST, Role.ADMIN)


# =============================================================================
# Configuração  (§2, §21 — nenhum secret no código)
# =============================================================================


def test_servico_recusa_subir_sem_credencial(monkeypatch) -> None:
    """Falhar no início, não na primeira requisição.

    Um serviço que sobe sem credencial e quebra no primeiro uso mostra o erro
    longe da causa — e mostra para o usuário.
    """
    get_settings.cache_clear()
    monkeypatch.delenv("FIREBASE_SERVICE_ACCOUNT", raising=False)

    with pytest.raises(ConfigError):
        get_settings()

    get_settings.cache_clear()


def test_credencial_incompleta_e_recusada(monkeypatch) -> None:
    get_settings.cache_clear()
    monkeypatch.setenv("FIREBASE_SERVICE_ACCOUNT", '{"type":"service_account"}')

    with pytest.raises(ConfigError) as erro:
        get_settings()

    # Os NOMES dos campos ausentes aparecem; os VALORES nunca apareceriam.
    assert "private_key" in str(erro.value)
    get_settings.cache_clear()


def test_credencial_nao_aparece_na_representacao(monkeypatch) -> None:
    """`repr` de um objeto de configuração acaba em log de erro.

    O campo é marcado com `repr=False` justamente para que a chave privada não
    vá junto quando alguém imprimir as configurações numa investigação.
    """
    get_settings.cache_clear()
    monkeypatch.setenv("FIREBASE_PROJECT_ID", "demo-scorpions")
    monkeypatch.setenv(
        "FIREBASE_SERVICE_ACCOUNT",
        '{"type":"service_account","project_id":"p",'
        '"private_key":"SEGREDO-QUE-NAO-PODE-VAZAR","client_email":"a@b"}',
    )

    texto = repr(get_settings())

    assert "SEGREDO-QUE-NAO-PODE-VAZAR" not in texto
    assert "private_key" not in texto
    get_settings.cache_clear()


def test_cors_nunca_nasce_com_curinga(monkeypatch) -> None:
    """Sem `ALLOWED_ORIGINS`, a lista é vazia — não `*`.

    Falhar fechado: um esquecimento de configuração bloqueia o navegador, em
    vez de liberar qualquer página a usar o token do usuário.
    """
    get_settings.cache_clear()
    monkeypatch.delenv("ALLOWED_ORIGINS", raising=False)
    monkeypatch.setenv("FIREBASE_PROJECT_ID", "demo-scorpions")
    monkeypatch.setenv(
        "FIREBASE_SERVICE_ACCOUNT",
        '{"type":"service_account","project_id":"p",'
        '"private_key":"k","client_email":"a@b"}',
    )

    assert get_settings().allowed_origins == ()
    get_settings.cache_clear()
