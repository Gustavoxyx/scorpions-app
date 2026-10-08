"""Formatos de entrada e saída da API.

O QUE NÃO ESTÁ AQUI, E É DE PROPÓSITO
-------------------------------------
`AnalysisRequest` não tem `userId`, `species`, `confidence` nem `modelVersion`.

Não é esquecimento: é o achado HIGH-1 da auditoria aplicado na forma dos
dados. O que o cliente não consegue nomear, ele não consegue forjar. O dono
sai do token verificado; o resultado sai do modelo, no servidor.

É a mesma ideia de `IdentificationResult.toClientCreateMap()` no Flutter — os dois
lados deixam os campos de resultado de fora, e a Security Rules recusa quem
tentar escrevê-los mesmo assim. Três camadas dizendo a mesma coisa.
"""

from __future__ import annotations

from typing import Literal

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
        formas = ("original", "processed", "thumbnail")
        extensoes = ("jpg", "png", "webp")
        # O sufixo `-2` é a segunda fotografia da mesma identificação. As duas
        # moram na mesma pasta; a regra do Storage aceita exatamente estes
        # nomes, e o aplicativo gera exatamente estes. Só `-2`: o pedido tem
        # teto de duas vistas, e não há terceiro arquivo para apontar.
        permitidos = {
            f"{forma}{sufixo}.{ext}"
            for forma in formas
            for sufixo in ("", "-2")
            for ext in extensoes
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


class SpeciesScore(BaseModel):
    """Uma hipótese de espécie, com a confiança que o modelo atribuiu."""

    speciesId: str = Field(max_length=64)
    scientificName: str = Field(max_length=120)
    confidence: float = Field(ge=0.0, le=1.0)


class FusionSummary(BaseModel):
    """O que as vistas disseram em conjunto.

    Os mesmos campos que o aplicativo lê em `fusion` no documento da
    identificação. Vale para fusão tardia e para um modelo de duas entradas:
    com um modelo conjunto, `agreement` simplesmente não vem.
    """

    viewCount: int = Field(ge=1, le=2)
    agreeOnTop1: bool | None = None
    agreement: float | None = Field(default=None, ge=0.0, le=1.0)
    decisionLevel: str = Field(max_length=32)
    reasons: list[str] = Field(default_factory=list, max_length=12)
    thresholdsCalibrated: bool


class AnalysisResponse(BaseModel):
    """O resultado de uma análise.

    CONTRATO PREPARADO, SEM IMPLEMENTAÇÃO. Nenhum endpoint devolve isto hoje:
    sem modelo, `POST /v1/analyses` responde 503. A forma está fixada para que
    a fase da IA seja preencher estes campos, e não negociar o formato com o
    aplicativo já escrito.

    Os nomes são os dos campos que só o servidor grava no Firestore — o que
    sai daqui e o que fica no documento são a mesma coisa.
    """

    sessionId: str
    requestId: str
    status: Literal[
        "processing", "identified", "low_confidence", "rejected", "error"
    ]

    species: SpeciesScore | None = None
    alternatives: list[SpeciesScore] = Field(default_factory=list, max_length=5)
    rejectionReason: str | None = Field(default=None, max_length=64)
    modelVersion: str | None = Field(default=None, max_length=64)
    fusion: FusionSummary | None = None

    # A decisão foi encaminhada a um revisor humano. Separado de `status` de
    # propósito: um resultado de baixa confiança pode ou não ir para revisão, e
    # misturar os dois num campo só obrigaria a inventar estados.
    needsHumanReview: bool = False


class QuotaResponse(BaseModel):
    """Consumo da cota de hoje.

    Serve para a tela avisar antes de o usuário tirar as fotos. Não é
    autorização: quem decide é `quota.consume`, dentro de uma transação.
    """

    used: int
    limit: int
    remaining: int


class DeletionResponse(BaseModel):
    """O recibo da exclusão de conta.

    # Por que devolve contagens
    Porque o titular acabou de pedir que algo irreversível acontecesse, e merece
    a confirmação de que aconteceu — "3 imagens e 2 análises apagadas" é
    verificável; "pronto" não é.

    # O que ele NÃO devolve
    Nenhum caminho de arquivo, nenhuma URL, nenhum identificador de documento.
    São contagens, e só. Dado pessoal numa resposta de exclusão seria o oposto
    do que a operação acabou de fazer.
    """

    deleted: bool
    images: int
    identifications: int
    requestId: str
