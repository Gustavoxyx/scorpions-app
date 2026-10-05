"""Validação do conteúdo real das imagens.

POR QUE ISTO EXISTE (LOW-1 da auditoria, §10 do briefing)
---------------------------------------------------------
A regra do Storage confere `request.resource.contentType`, e o comentário dela
já dizia a verdade: *"`contentType` é informado pelo cliente e pode mentir. Esta
regra barra o descuidado, não o mal-intencionado."*

O §10 é direto: *"Nunca confiar na extensão do arquivo. Validar no backend:
tamanho, MIME real, magic bytes, formato, dimensões."* Este arquivo é esse
backend.

O que um arquivo que mente consegue hoje é limitado — ele fica num caminho
privado e nada o executa. Mas com inferência real ele entra num decodificador
de imagem, e decodificadores são historicamente onde moram as falhas de
corrupção de memória. Validar antes de decodificar é a ordem certa.

O QUE ESTA VALIDAÇÃO NÃO É
--------------------------
Não é antivírus e não substitui o decodificador. Ela confirma que os bytes
**começam como** o formato declarado e que as dimensões são plausíveis. Um JPEG
válido mas malicioso passa por aqui — e é por isso que a decodificação roda
depois, com limite de tamanho, e não em cima do arquivo original.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class ImageFormat(str, Enum):
    JPEG = "jpeg"
    PNG = "png"
    WEBP = "webp"

    @property
    def mime(self) -> str:
        return f"image/{self.value}"


class RejectionCode(str, Enum):
    """Por que a imagem foi recusada.

    Códigos, não frases: a mensagem ao usuário é montada na borda, e o código é
    o que vai para o log e para o teste. Comparar frases em teste é como a
    tradução quebra o CI.
    """

    EMPTY = "empty"
    TOO_SMALL = "too_small"
    TOO_LARGE = "too_large"
    UNKNOWN_FORMAT = "unknown_format"
    FORMAT_MISMATCH = "format_mismatch"
    DIMENSIONS_UNREADABLE = "dimensions_unreadable"
    DIMENSIONS_TOO_SMALL = "dimensions_too_small"
    DIMENSIONS_TOO_LARGE = "dimensions_too_large"


@dataclass(frozen=True)
class ImageCheck:
    """O veredito. Imagem recusada é um resultado, não uma exceção."""

    ok: bool
    detected: ImageFormat | None = None
    width: int | None = None
    height: int | None = None
    reason: RejectionCode | None = None

    @property
    def megapixels(self) -> float:
        if not self.width or not self.height:
            return 0.0
        return (self.width * self.height) / 1_000_000


# -- Limites -------------------------------------------------------------------
#
# Espelham `ImageLimits` do Flutter de propósito. Os números são duplicados nas
# três camadas — aplicativo, regra do Storage e aqui — e isso é deliberado: o
# aplicativo valida para não gastar a rede do usuário com um envio que seria
# recusado, a regra valida porque o envio vai direto para o Storage, e **este**
# é o que tem a palavra final.
#
# O risco de duplicar é sair de sincronia. O controle é o teste de contrato que
# compara os três.

MIN_BYTES = 8 * 1024
MAX_BYTES = 8 * 1024 * 1024
MIN_DIMENSION = 480
MAX_DIMENSION = 6000

#: Bytes iniciais de cada formato. É a identidade real do arquivo — o que a
#: extensão e o `Content-Type` apenas afirmam.
_ASSINATURAS: tuple[tuple[bytes, ImageFormat], ...] = (
    (b"\xff\xd8\xff", ImageFormat.JPEG),
    (b"\x89PNG\r\n\x1a\n", ImageFormat.PNG),
    # WebP é `RIFF....WEBP`: os quatro bytes do meio são o tamanho e variam,
    # então a verificação é em duas partes (ver `detect_format`).
)


def detect_format(data: bytes) -> ImageFormat | None:
    """O formato real, pelos bytes iniciais. `None` se não reconhecido."""
    for assinatura, formato in _ASSINATURAS:
        if data.startswith(assinatura):
            return formato

    if len(data) >= 12 and data[0:4] == b"RIFF" and data[8:12] == b"WEBP":
        return ImageFormat.WEBP

    return None


def read_dimensions(data: bytes, formato: ImageFormat) -> tuple[int, int] | None:
    """Largura e altura, lidas do cabeçalho.

    Sem decodificar a imagem inteira, e isso é o ponto: uma imagem de 20.000 por
    20.000 pixels ocupa 1,6 GB em RGBA. Descobrir o tamanho **depois** de
    decodificar é descobrir tarde — o processo já morreu.

    É o mesmo raciocínio do comentário de `ImageLimits.maxDimension` no Flutter:
    *"Recusamos antes de decodificar."*
    """
    try:
        if formato is ImageFormat.PNG:
            # IHDR é o primeiro bloco e tem posição fixa.
            if len(data) < 24:
                return None
            largura = int.from_bytes(data[16:20], "big")
            altura = int.from_bytes(data[20:24], "big")
            return (largura, altura) if largura and altura else None

        if formato is ImageFormat.JPEG:
            return _dimensoes_jpeg(data)

        if formato is ImageFormat.WEBP:
            return _dimensoes_webp(data)
    except Exception:  # noqa: BLE001
        # Cabeçalho truncado ou malformado. `None` faz a validação recusar com
        # `DIMENSIONS_UNREADABLE` — falhar fechado, não adivinhar um tamanho.
        return None

    return None


def validate(
    data: bytes,
    *,
    declared_content_type: str | None = None,
) -> ImageCheck:
    """Confere tamanho, formato real e dimensões.

    [declared_content_type] é o que o **cliente afirmou**. Ele é usado para
    comparar com o que os bytes dizem, nunca para decidir: um arquivo cujo
    conteúdo contradiz a declaração é recusado com `FORMAT_MISMATCH`, e essa
    discordância é informação — ela separa o descuidado do mal-intencionado.
    """
    if not data:
        return ImageCheck(ok=False, reason=RejectionCode.EMPTY)

    if len(data) < MIN_BYTES:
        # Uma fotografia de escorpião utilizável não cabe em 8 KB; abaixo disso
        # é ícone, avatar ou arquivo truncado.
        return ImageCheck(ok=False, reason=RejectionCode.TOO_SMALL)

    if len(data) > MAX_BYTES:
        return ImageCheck(ok=False, reason=RejectionCode.TOO_LARGE)

    formato = detect_format(data)
    if formato is None:
        return ImageCheck(ok=False, reason=RejectionCode.UNKNOWN_FORMAT)

    if declared_content_type:
        declarado = declared_content_type.split(";")[0].strip().lower()
        # `image/jpg` não é um tipo MIME válido, mas aparece na prática. Tratar
        # como `image/jpeg` evita recusar um cliente correto por um detalhe de
        # nomenclatura que não é um ataque.
        if declarado == "image/jpg":
            declarado = "image/jpeg"
        if declarado != formato.mime:
            return ImageCheck(
                ok=False, detected=formato, reason=RejectionCode.FORMAT_MISMATCH
            )

    dimensoes = read_dimensions(data, formato)
    if dimensoes is None:
        return ImageCheck(
            ok=False, detected=formato, reason=RejectionCode.DIMENSIONS_UNREADABLE
        )

    largura, altura = dimensoes

    if min(largura, altura) < MIN_DIMENSION:
        # Abaixo de 480px os caracteres que distinguem as espécies — granulação
        # do tegumento, proporção das pinças, segmentos da cauda — deixam de
        # estar na imagem. Aceitar seria prometer uma análise impossível.
        return ImageCheck(
            ok=False,
            detected=formato,
            width=largura,
            height=altura,
            reason=RejectionCode.DIMENSIONS_TOO_SMALL,
        )

    if max(largura, altura) > MAX_DIMENSION:
        return ImageCheck(
            ok=False,
            detected=formato,
            width=largura,
            height=altura,
            reason=RejectionCode.DIMENSIONS_TOO_LARGE,
        )

    return ImageCheck(ok=True, detected=formato, width=largura, height=altura)


# -- Leitura de cabeçalho ------------------------------------------------------


def _dimensoes_jpeg(data: bytes) -> tuple[int, int] | None:
    """Percorre os segmentos até achar um Start Of Frame.

    JPEG não tem as dimensões em posição fixa: é uma sequência de segmentos, e
    o tamanho está no SOF, que pode vir depois de EXIF, de miniatura e de perfil
    de cor. Daí a varredura.
    """
    i = 2  # pula o SOI (0xFFD8)
    limite = len(data)

    while i < limite - 9:
        if data[i] != 0xFF:
            i += 1
            continue

        marcador = data[i + 1]

        # Preenchimento entre segmentos.
        if marcador == 0xFF:
            i += 1
            continue

        # SOF0..SOF15, exceto os que não carregam dimensão (DHT=C4, JPG=C8,
        # DAC=CC).
        if 0xC0 <= marcador <= 0xCF and marcador not in (0xC4, 0xC8, 0xCC):
            altura = int.from_bytes(data[i + 5 : i + 7], "big")
            largura = int.from_bytes(data[i + 7 : i + 9], "big")
            return (largura, altura) if largura and altura else None

        # Marcadores sem carga.
        if marcador in (0xD8, 0xD9) or 0xD0 <= marcador <= 0xD7:
            i += 2
            continue

        # SOS: daqui para frente é dado comprimido, não há mais cabeçalho.
        if marcador == 0xDA:
            return None

        tamanho = int.from_bytes(data[i + 2 : i + 4], "big")
        if tamanho < 2:
            return None
        i += 2 + tamanho

    return None


def _dimensoes_webp(data: bytes) -> tuple[int, int] | None:
    """Lê VP8, VP8L ou VP8X — os três sabores de WebP.

    Os três guardam o tamanho em lugares e codificações diferentes. Um WebP
    gerado por celular costuma ser VP8L ou VP8X; por isso nenhum dos três pode
    faltar.
    """
    if len(data) < 30:
        return None

    tipo = data[12:16]

    if tipo == b"VP8 ":
        # Quadro-chave: 3 bytes de tag, 3 de código de início, então 14 bits de
        # largura e 14 de altura.
        if len(data) < 30:
            return None
        largura = int.from_bytes(data[26:28], "little") & 0x3FFF
        altura = int.from_bytes(data[28:30], "little") & 0x3FFF
        return (largura, altura) if largura and altura else None

    if tipo == b"VP8L":
        # 14 bits de largura e 14 de altura, empacotados, menos um.
        bits = int.from_bytes(data[21:25], "little")
        largura = (bits & 0x3FFF) + 1
        altura = ((bits >> 14) & 0x3FFF) + 1
        return largura, altura

    if tipo == b"VP8X":
        # Canvas em 24 bits por dimensão, menos um.
        largura = int.from_bytes(data[24:27], "little") + 1
        altura = int.from_bytes(data[27:30], "little") + 1
        return largura, altura

    return None
