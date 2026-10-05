"""API de inferência do Scorpions.

POR QUE ESTE SERVIÇO EXISTE
---------------------------
A auditoria (HIGH-1) encontrou que o aplicativo escrevia `confidence` e
`modelVersion` direto no Firestore. A regra validava o formato, não a origem —
um `0.99` forjado passava igual a um produzido por modelo.

Sem IA isso quase não importava. Com IA, um registro forjado contaminaria as
métricas, entraria na fila de revisão humana como se fosse saída do modelo, e
alimentaria o dataset de retreinamento com rótulo falso. O §11 do briefing de
segurança é direto: *"Nunca permitir que o usuário simplesmente envie
confidence = 0.99 e isso seja salvo."*

Então o resultado passa a nascer aqui, onde o cliente não alcança, e as
Security Rules passam a recusar a escrita desses campos vinda do aplicativo.

O QUE ESTE SERVIÇO NUNCA FAZ
----------------------------
- Confiar em `userId`, `species`, `confidence` ou `role` enviados no corpo.
  O `uid` sai do token verificado; o resto é calculado aqui.
- Devolver detalhe interno numa mensagem de erro (§17).
- Registrar imagem, token ou dado pessoal em log (§18).
"""

from __future__ import annotations

import logging
import uuid
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from . import account, quota
from .audit import AuditAction, AuditOutcome, record
from .auth import Caller, Role, current_caller, firebase_app
from .config import ConfigError, Settings, get_settings
from .fusion import CALIBRATED
from .schemas import (
    AnalysisRequest,
    AnalysisResponse,
    DeletionResponse,
    HealthResponse,
    QuotaResponse,
)

log = logging.getLogger("scorpions")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Falha no início, não na primeira requisição.

    Um serviço que sobe sem credencial e só quebra quando o primeiro usuário
    tenta usar é pior que um que não sobe: o erro aparece longe da causa, e
    aparece para o usuário.
    """
    try:
        settings = get_settings()
        firebase_app(settings)
        log.info(
            "serviço pronto",
            extra={"project": settings.project_id, "calibrated": CALIBRATED},
        )
    except ConfigError as erro:
        log.error("configuração inválida: %s", erro)
        raise
    yield


app = FastAPI(
    title="Scorpions — Serviço de inferência",
    version="0.1.0",
    lifespan=lifespan,
    # A documentação interativa fica fora do ar por padrão: ela descreve a
    # superfície inteira da API para qualquer visitante. Em desenvolvimento,
    # sobe com `--reload` e `ENABLE_DOCS=1`.
    docs_url=None,
    redoc_url=None,
    openapi_url=None,
)


def _settings_safe() -> Settings | None:
    try:
        return get_settings()
    except ConfigError:
        return None


_cfg = _settings_safe()
app.add_middleware(
    CORSMiddleware,
    # Lista explícita, nunca `*` (§16). Com curinga, qualquer página poderia
    # disparar pedidos usando o token do usuário.
    allow_origins=list(_cfg.allowed_origins) if _cfg else [],
    allow_credentials=True,
    allow_methods=["GET", "POST"],
    allow_headers=["Authorization", "Content-Type"],
    max_age=600,
)


@app.middleware("http")
async def correlation_id(request: Request, call_next):
    """Dá a cada requisição um identificador rastreável (§18).

    Vai no log e na resposta. Quando o usuário relatar um problema, o
    identificador liga o relato à linha de log — sem precisar que ele descreva
    o que viu, e sem o log guardar quem ele é.
    """
    rid = uuid.uuid4().hex[:12]
    request.state.request_id = rid
    resposta = await call_next(request)
    resposta.headers["X-Request-Id"] = rid
    return resposta


@app.exception_handler(Exception)
async def unhandled(request: Request, exc: Exception) -> JSONResponse:
    """Último anteparo contra vazamento de detalhe interno (§17).

    O traço técnico vai para o log do servidor com o identificador da
    requisição. O cliente recebe uma frase e o identificador — nada de pilha
    de chamadas, caminho de arquivo ou nome de classe.
    """
    rid = getattr(request.state, "request_id", "?")
    log.exception("erro não tratado", extra={"request_id": rid})
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "detail": "Não foi possível processar a solicitação.",
            "requestId": rid,
        },
    )


@app.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    """Sem autenticação de propósito — é o que o provedor consulta.

    Não diz nada sobre a configuração além de estar presente ou não: um
    verificador de saúde que lista variáveis de ambiente é um vazamento com
    outro nome.
    """
    cfg = _settings_safe()
    return HealthResponse(
        status="ok" if cfg else "unconfigured",
        thresholdsCalibrated=CALIBRATED,
        modelAvailable=False,
    )


@app.post("/v1/analyses", response_model=AnalysisResponse)
async def create_analysis(
    payload: AnalysisRequest,
    request: Request,
    caller: Caller = Depends(current_caller),
    settings: Settings = Depends(get_settings),
) -> AnalysisResponse:
    """Analisa as imagens de uma sessão e grava o resultado.

    O corpo diz **quais imagens** olhar; não diz de quem são, nem o que elas
    mostram. O dono sai de `caller.uid`, verificado a partir do token.
    """
    rid = getattr(request.state, "request_id", "?")

    # O caminho carrega o dono. Um `sessionId` apontando para a pasta de outra
    # pessoa não encontra nada, porque o prefixo é montado a partir do uid
    # verificado — não do que veio no corpo. É o IDOR fechado por construção.
    prefixo = f"users/{caller.uid}/identifications/{payload.sessionId}"
    del prefixo  # usado quando o modelo existir; aqui só documenta a construção

    # A cota é cobrada ANTES de qualquer trabalho (MEDIUM-4).
    #
    # Antes de propósito: cobrar depois significaria que uma análise abandonada
    # no meio sai de graça, e provocar abandono é barato. O §17 chama isso de
    # proteger o orçamento, e enquanto não houver modelo isto já protege a cota
    # do Firestore e do Storage.
    try:
        estado = quota.consume(settings, caller.uid)
    except HTTPException as erro:
        if erro.status_code == status.HTTP_429_TOO_MANY_REQUESTS:
            record(
                settings,
                action=AuditAction.QUOTA_EXCEEDED,
                actor_uid=caller.uid,
                outcome=AuditOutcome.DENIED,
                request_id=rid,
            )
        raise

    log.info(
        "análise solicitada",
        extra={
            "request_id": rid,
            "views": len(payload.views),
            "quota_remaining": estado.remaining,
            # Sem uid, sem e-mail, sem caminho — §18.
        },
    )

    # O modelo ainda não existe, e isto é dito em voz alta em vez de
    # devolvido como resultado vazio que a tela interpretaria como "nada
    # encontrado". O §12 da Fase 5 proíbe fingir que o modelo existe.
    raise HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail=(
            "A análise por modelo ainda não está disponível. "
            "Suas fotos foram guardadas e nada foi descartado."
        ),
        headers={"X-Request-Id": rid, "Retry-After": "3600"},
    )


@app.get("/v1/me/quota", response_model=QuotaResponse)
async def read_quota(
    caller: Caller = Depends(current_caller),
    settings: Settings = Depends(get_settings),
) -> QuotaResponse:
    """Quanto da cota de hoje já foi usado.

    Para a tela avisar antes de o usuário tirar as fotos. **Não** é o que
    autoriza — entre esta leitura e o uso o número pode mudar, e quem
    decide é `quota.consume`, dentro de uma transação."""
    estado = quota.peek(settings, caller.uid)
    return QuotaResponse(
        used=estado.used, limit=estado.limit, remaining=estado.remaining
    )


@app.get("/v1/me/data")
async def export_my_data(
    request: Request,
    caller: Caller = Depends(current_caller),
    settings: Settings = Depends(get_settings),
) -> dict:
    """Exporta os dados do titular (LGPD, Art. 18, V — portabilidade).

    Sem exigir reautenticação: é uma leitura do que o próprio usuário já vê
    no aplicativo, e o token verificado basta. Pedir senha para ler o que a
    tela mostra seria atrito sem ganho."""
    rid = getattr(request.state, "request_id", "?")
    return account.export_data(settings, caller, rid)


@app.delete("/v1/me", response_model=DeletionResponse)
async def delete_my_account(
    request: Request,
    caller: Caller = Depends(current_caller),
    settings: Settings = Depends(get_settings),
) -> DeletionResponse:
    """Apaga a conta e tudo que pertence a ela (LGPD, Art. 18, VI).

    Era o HIGH-2 da auditoria: o titular não tinha **nenhum** caminho para
    apagar os próprios dados.

    # Por que exige senha recente
    É a operação irreversível por definição. Um aparelho destravado
    esquecido numa mesa, ou um token roubado, não podem bastar — e o ID
    token do Firebase se renova sozinho a cada hora, sem pedir senha.
    `requires_recent_auth` olha a claim `auth_time`, que só se move quando
    a senha é apresentada de fato (MEDIUM-5).

    O cliente responde a isto chamando `reauthenticateWithCredential` e
    pedindo um token novo; o cabeçalho `X-Reauth-Required` na recusa é o
    sinal."""
    rid = getattr(request.state, "request_id", "?")
    caller.requires_recent_auth()

    relatorio = account.delete_account(settings, caller, rid)

    return DeletionResponse(
        deleted=True,
        images=relatorio.images,
        identifications=relatorio.identifications,
        requestId=rid,
    )


@app.get("/v1/review-queue")
async def review_queue(
    request: Request,
    caller: Caller = Depends(current_caller),
    settings: Settings = Depends(get_settings),
) -> dict:
    """Fila de revisão (§19). Só para quem revisa.

    A verificação acontece aqui, no servidor. Esconder o item de menu no
    aplicativo não é controle de acesso — é decoração sobre um endpoint que
    continuaria respondendo a quem soubesse o caminho.
    """
    caller.requires(Role.SPECIALIST, Role.REVIEWER, Role.ADMIN)

    # Acesso privilegiado a dado de outras pessoas gera registro (FASE 24).
    #
    # Hoje a fila está vazia, então não há o que ver — mas o registro começa a
    # existir junto do endpoint, não depois. O modelo de ameaças marca em T-4
    # que uma conta privilegiada comprometida leria dados de usuários sem deixar
    # rastro; é esta linha que fecha isso, antes de haver o que ler.
    record(
        settings,
        action=AuditAction.REVIEW_QUEUE_ACCESSED,
        actor_uid=caller.uid,
        outcome=AuditOutcome.SUCCESS,
        request_id=getattr(request.state, "request_id", "?"),
    )
    return {"items": [], "pending": 0}
