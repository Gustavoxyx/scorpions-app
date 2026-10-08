"""O caminho das imagens até o modelo — sem o modelo.

Este módulo é a costura onde a inferência entra. Ele faz hoje o que não depende
de haver modelo: buscar as imagens da sessão e **conferir o que elas são** antes
de qualquer coisa olhar para elas.

A validação de `images.py` estava pronta e nenhum endpoint a chamava. Uma
verificação de segurança que não está no caminho não verifica nada; ela passa a
estar aqui, no único lugar por onde uma imagem chega à análise.

O QUE ESTE MÓDULO NÃO DECIDE
----------------------------
Qual é o modelo, se ele recebe uma imagem ou duas, se a fusão é tardia ou
conjunta. `Analyzer` recebe a sessão inteira de uma vez justamente para que
essa decisão caiba atrás dele, em qualquer das formas.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Protocol

from fastapi import HTTPException, status

from . import images
from .clients import storage_bucket
from .config import Settings
from .schemas import AnalysisRequest, AnalysisResponse

log = logging.getLogger("scorpions")


@dataclass(frozen=True)
class LoadedView:
    """Uma imagem da sessão, já conferida."""

    capture_type: str
    file_name: str
    check: images.ImageCheck
    # Fora do `repr`: bytes de imagem não vão para log nem para mensagem de erro.
    data: bytes = field(repr=False)


class Analyzer(Protocol):
    """O contrato da inferência.

    Recebe **todas** as vistas da sessão de uma vez e devolve a resposta
    completa. Um classificador por imagem com fusão depois cabe aqui; um modelo
    de duas entradas também.
    """

    def analyze(
        self, *, session_id: str, request_id: str, views: list[LoadedView]
    ) -> AnalysisResponse: ...


def get_analyzer() -> Analyzer | None:
    """O analisador em uso. `None` enquanto não houver modelo.

    Devolver um analisador que sorteia espécies para "o fluxo funcionar" é o que
    este projeto se recusa a fazer: um resultado inventado no servidor seria
    gravado como saída de modelo.
    """
    return None


def load_views(
    settings: Settings, uid: str, payload: AnalysisRequest
) -> list[LoadedView]:
    """Busca as imagens da sessão no Storage e confere cada uma.

    O caminho é montado a partir do `uid` **verificado**: um `sessionId`
    apontando para a pasta de outra pessoa não encontra nada.

    Sem bucket configurado devolve lista vazia — o Storage de produção ainda não
    existe, e fingir que as imagens foram conferidas seria pior que dizer que
    não foram. Quem chama registra isso.
    """
    if not settings.storage_bucket:
        return []

    prefixo = f"users/{uid}/identifications/{payload.sessionId}"

    try:
        bucket = storage_bucket(settings)
    except Exception as erro:  # noqa: BLE001
        raise _indisponivel() from erro

    vistas: list[LoadedView] = []
    for vista in payload.views:
        try:
            blob = bucket.get_blob(f"{prefixo}/{vista.fileName}")
        except Exception as erro:  # noqa: BLE001
            raise _indisponivel() from erro

        if blob is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Imagem não encontrada. Envie a fotografia antes de "
                "pedir a análise.",
            )

        # O tamanho é conferido nos metadados, ANTES de baixar. Baixar um
        # arquivo de centenas de megabytes para então recusá-lo seria gastar a
        # memória do processo a pedido de qualquer cliente.
        if (blob.size or 0) > settings.max_image_bytes:
            raise _recusada(images.RejectionCode.TOO_LARGE)

        try:
            dados = blob.download_as_bytes()
        except Exception as erro:  # noqa: BLE001
            raise _indisponivel() from erro

        conferida = images.validate(
            dados, declared_content_type=blob.content_type
        )
        if not conferida.ok:
            log.warning(
                "imagem recusada",
                extra={"reason": getattr(conferida.reason, "value", "unknown")},
            )
            raise _recusada(conferida.reason)

        vistas.append(
            LoadedView(
                capture_type=vista.captureType,
                file_name=vista.fileName,
                check=conferida,
                data=dados,
            )
        )
    return vistas


def _recusada(motivo: images.RejectionCode | None) -> HTTPException:
    return HTTPException(
        status_code=422,
        detail="Esta imagem não pôde ser usada. Tire outra fotografia.",
        headers={"X-Image-Rejection": getattr(motivo, "value", "unknown")},
    )


def _indisponivel() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail="Não foi possível ler as imagens agora. Tente novamente.",
        headers={"Retry-After": "60"},
    )
