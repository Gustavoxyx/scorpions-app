"""Formatos de entrada e saída da API.

O QUE NÃO ESTÁ AQUI, E É DE PROPÓSITO
-------------------------------------
`AnalysisRequest` não tem `userId`, `species`, `confidence` nem `modelVersion`.

Não é esquecimento: é o achado HIGH-1 da auditoria aplicado na forma dos
dados. O que o cliente não consegue nomear, ele não consegue forjar. O dono
sai do token verificado; o resultado sai do modelo, no servidor.

É a mesma ideia de `IdentificationSession.toClientMap()` no Flutter — os dois
lados deixam os campos de resultado de fora, e a Security Rules recusa quem
tentar escrevê-los mesmo assim. Três camadas dizendo a mesma coisa.
"""

from __future__ import annotations

from pydantic import BaseModel, Field, field_validator


class ViewRef(BaseModel):
    """Referência a uma imagem já enviada ao Storage."""

    captureType: str = Field(max_length=32)
    fileName: str = Field(max_length=64)

    @field_validator("fileName")
    @classmethod
    def _nome_previsto(cls, v: str) -> str:
        """Só os nomes que o pipeline gera.

        Fecha travessia de caminho (`../`) e qualquer tentativa de apontar
        para fora da pasta da sessão. A mesma lista existe na regra do
        Storage; aqui ela é conferida de novo, porque o servidor não herda a
        confiança de outra camada.
        """
        permitidos = {
            "original.jpg", "processed.jpg", "thumbnail.jpg",
            "original.png", "processed.png", "thumbnail.png",
            "original.webp", "processed.webp", "thumbnail.webp",
        }
        if v not in permitidos:
            raise ValueError("nome de arquivo não previsto")
        return v

    @field_validator("captureType")
    @classmethod
    def _tipo_conhecido(cls, v: str) -> str:
        permitidos = {
            "top_view", "close_up", "pedipalp",
            "tail", "telson", "general_side_view",
        }
        if v not in permitidos:
            raise ValueError("tipo de captura desconhecido")
        return v


class AnalysisRequest(BaseModel):
    """O pedido de análise.

    `sessionId` identifica a pasta; ele é combinado com o uid do token para
    montar o caminho, então apontar para a sessão de outra pessoa não alcança
    nada.
    """

    sessionId: str = Field(min_length=8, max_length=64, pattern=r"^[a-z0-9]+$")
    views: list[ViewRef] = Field(min_length=1, max_length=2)

    model_config = {"extra": "forbid"}
    # `extra: forbid` fecha mass assignment: um corpo com `role: "admin"` ou
    # `confidence: 0.99` é recusado em vez de ignorado em silêncio. Recusar é
    # melhor — o cliente descobre que tentou algo que não existe.


class HealthResponse(BaseModel):
    status: str
    thresholdsCalibrated: bool
    modelAvailable: bool


class AnalysisResponse(BaseModel):
    sessionId: str
    status: str
    requestId: str
