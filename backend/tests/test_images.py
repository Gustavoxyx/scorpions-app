"""Testes da validação de conteúdo real das imagens.

O que está sendo verificado é o achado LOW-1: `contentType` vem do cliente e
pode mentir. Então cada caso aqui é um arquivo que **afirma** uma coisa e **é**
outra, ou que é grande demais, pequeno demais, ou não é imagem nenhuma.

Os arquivos são construídos byte a byte, não lidos de uma pasta de amostras. É
deliberado: um teste que depende de arquivo externo falha quando alguém move a
pasta, e ninguém sabe se o código quebrou ou se o arquivo sumiu.
"""

from __future__ import annotations

import os
import struct

import pytest

os.environ.setdefault("FIREBASE_PROJECT_ID", "demo-scorpions")
os.environ.setdefault(
    "FIREBASE_SERVICE_ACCOUNT",
    '{"type":"service_account","project_id":"demo-scorpions",'
    '"private_key":"nao-e-uma-chave","client_email":"teste@exemplo"}',
)

from app.images import (  # noqa: E402
    MAX_BYTES,
    MIN_BYTES,
    ImageFormat,
    RejectionCode,
    detect_format,
    read_dimensions,
    validate,
)


# =============================================================================
# Construtores de arquivo
# =============================================================================


def _encher(cabecalho: bytes, tamanho: int = MIN_BYTES + 1024) -> bytes:
    """Completa até [tamanho] para que o arquivo passe do piso de bytes.

    O preenchimento é zero. Não é um arquivo decodificável — e não precisa ser:
    o que está sob teste é a leitura de **cabeçalho**, que acontece antes de
    qualquer decodificação. É justamente o ponto da validação.
    """
    return cabecalho + b"\x00" * max(0, tamanho - len(cabecalho))


def jpeg(largura: int = 1600, altura: int = 1200) -> bytes:
    """JPEG com um SOF0 depois de um APP0, como um arquivo de câmera real."""
    cabecalho = bytearray(b"\xff\xd8\xff")
    # APP0 (JFIF), 16 bytes de carga — está aqui para que o leitor tenha de
    # percorrer um segmento antes de achar o SOF.
    cabecalho += b"\xe0" + struct.pack(">H", 16) + b"JFIF\x00" + b"\x00" * 9
    # SOF0: tamanho, precisão, altura, largura, componentes
    cabecalho += b"\xff\xc0" + struct.pack(">H", 17) + b"\x08"
    cabecalho += struct.pack(">H", altura) + struct.pack(">H", largura)
    cabecalho += b"\x03" + b"\x00" * 9
    return _encher(bytes(cabecalho))


def png(largura: int = 1600, altura: int = 1200) -> bytes:
    cabecalho = b"\x89PNG\r\n\x1a\n"
    cabecalho += struct.pack(">I", 13) + b"IHDR"
    cabecalho += struct.pack(">I", largura) + struct.pack(">I", altura)
    cabecalho += b"\x08\x06\x00\x00\x00"
    return _encher(cabecalho)


def webp_vp8x(largura: int = 1600, altura: int = 1200) -> bytes:
    corpo = bytearray(b"WEBP")
    corpo += b"VP8X" + struct.pack("<I", 10) + b"\x00" * 4
    corpo += (largura - 1).to_bytes(3, "little")
    corpo += (altura - 1).to_bytes(3, "little")
    return _encher(b"RIFF" + struct.pack("<I", len(corpo)) + bytes(corpo))


def webp_vp8l(largura: int = 1600, altura: int = 1200) -> bytes:
    corpo = bytearray(b"WEBP")
    corpo += b"VP8L" + struct.pack("<I", 20) + b"\x2f"
    bits = (largura - 1) | ((altura - 1) << 14)
    corpo += struct.pack("<I", bits)
    corpo += b"\x00" * 16
    return _encher(b"RIFF" + struct.pack("<I", len(corpo)) + bytes(corpo))


# =============================================================================
# Detecção de formato pelos bytes
# =============================================================================


# Os parâmetros são **construtores**, não os bytes.
#
# O pytest escreve a representação de cada parâmetro no identificador do teste, e
# o identificador vai para a variável de ambiente `PYTEST_CURRENT_TEST`. Passar
# 9 KB de bytes por caso estourou o limite de 32767 caracteres de variável de
# ambiente no Windows — todos os casos falharam com `ValueError`, e nenhum deles
# por causa do código sob teste.
@pytest.mark.parametrize(
    ("construtor", "esperado"),
    [
        (jpeg, ImageFormat.JPEG),
        (png, ImageFormat.PNG),
        (webp_vp8x, ImageFormat.WEBP),
        (webp_vp8l, ImageFormat.WEBP),
    ],
    ids=["jpeg", "png", "webp-vp8x", "webp-vp8l"],
)
def test_formato_e_detectado_pelos_bytes(construtor, esperado) -> None:
    assert detect_format(construtor()) is esperado


@pytest.mark.parametrize(
    ("prefixo", "rotulo"),
    [
        (b"", "vazio"),
        (b"GIF89a", "gif"),  # formato real de imagem, mas não suportado
        (b"%PDF-1.7", "pdf"),
        (b"PK\x03\x04", "zip"),  # e portanto APK, DOCX, JAR
        (b"#!/bin/sh\nrm -rf /", "shell"),
        (b"<svg xmlns=", "svg"),  # SVG carrega script
        (b"\x7fELF", "elf"),
        (b"MZ", "exe-windows"),
    ],
    ids=lambda v: v if isinstance(v, str) else "",
)
def test_o_que_nao_e_imagem_suportada_nao_e_reconhecido(
    prefixo: bytes, rotulo: str
) -> None:
    del rotulo  # só nomeia o caso
    assert detect_format(prefixo + b"\x00" * 100) is None


def test_riff_que_nao_e_webp_nao_passa() -> None:
    """Um WAV começa com `RIFF` igual a um WebP.

    Verificar só os quatro primeiros bytes aceitaria áudio como imagem. É por
    isso que a detecção de WebP olha também os bytes 8 a 12.
    """
    wav = b"RIFF" + struct.pack("<I", 100) + b"WAVE" + b"\x00" * 100
    assert detect_format(wav) is None


# =============================================================================
# Dimensões, lidas do cabeçalho
# =============================================================================


@pytest.mark.parametrize(
    ("construtor", "formato"),
    [
        (jpeg, ImageFormat.JPEG),
        (png, ImageFormat.PNG),
        (webp_vp8x, ImageFormat.WEBP),
        (webp_vp8l, ImageFormat.WEBP),
    ],
)
def test_dimensoes_saem_do_cabecalho(construtor, formato) -> None:
    assert read_dimensions(construtor(1600, 1200), formato) == (1600, 1200)
    assert read_dimensions(construtor(640, 480), formato) == (640, 480)


def test_cabecalho_truncado_nao_adivinha_dimensao() -> None:
    """Falhar fechado: sem cabeçalho legível, `None`, não um palpite."""
    assert read_dimensions(b"\x89PNG\r\n\x1a\n", ImageFormat.PNG) is None
    assert read_dimensions(b"\xff\xd8\xff", ImageFormat.JPEG) is None
    assert read_dimensions(b"RIFF", ImageFormat.WEBP) is None


def test_jpeg_sem_sof_nao_devolve_dimensao() -> None:
    """Um JPEG que entra em dados comprimidos sem SOF não tem o que ler."""
    dados = b"\xff\xd8\xff\xda" + b"\x00" * 200
    assert read_dimensions(dados, ImageFormat.JPEG) is None


# =============================================================================
# O veredito completo
# =============================================================================


def test_imagem_plausivel_passa() -> None:
    r = validate(jpeg(1600, 1200), declared_content_type="image/jpeg")

    assert r.ok
    assert r.detected is ImageFormat.JPEG
    assert (r.width, r.height) == (1600, 1200)
    assert r.reason is None


def test_image_jpg_e_tratado_como_jpeg() -> None:
    """`image/jpg` não é tipo MIME válido, mas aparece na prática.

    Recusar um cliente correto por um detalhe de nomenclatura não é segurança,
    é atrito.
    """
    assert validate(jpeg(), declared_content_type="image/jpg").ok


def test_content_type_com_parametro_nao_quebra() -> None:
    assert validate(jpeg(), declared_content_type="image/jpeg; charset=utf-8").ok


def test_sem_declaracao_a_validacao_ainda_funciona() -> None:
    """A declaração do cliente é opcional — ela só serve para contradizer.

    Quem manda é o conteúdo.
    """
    r = validate(jpeg())
    assert r.ok
    assert r.detected is ImageFormat.JPEG


# -- O achado LOW-1, no centro -------------------------------------------------


def test_executavel_que_se_diz_jpeg_e_recusado() -> None:
    """O caso que a regra do Storage não pega.

    A regra confere o `contentType` declarado; aqui o conteúdo é que decide.
    """
    executavel = _encher(b"MZ\x90\x00")

    r = validate(executavel, declared_content_type="image/jpeg")

    assert not r.ok
    assert r.reason is RejectionCode.UNKNOWN_FORMAT


def test_png_que_se_diz_jpeg_e_recusado_por_divergencia() -> None:
    """Conteúdo válido, declaração errada.

    Pode ser cliente com defeito ou tentativa de contornar uma regra que olha
    só a declaração. Nos dois casos, a divergência é informação — e recusar com
    um código próprio a preserva no log, em vez de tratar como formato
    desconhecido.
    """
    r = validate(png(), declared_content_type="image/jpeg")

    assert not r.ok
    assert r.reason is RejectionCode.FORMAT_MISMATCH
    assert r.detected is ImageFormat.PNG  # o que ele é de verdade


def test_svg_renomeado_e_recusado() -> None:
    """SVG carrega script. Nunca entra como imagem de usuário."""
    svg = _encher(b'<svg xmlns="http://www.w3.org/2000/svg"><script/></svg>')

    assert not validate(svg, declared_content_type="image/png").ok


# -- Tamanho -------------------------------------------------------------------


def test_arquivo_vazio_e_recusado() -> None:
    assert validate(b"").reason is RejectionCode.EMPTY


def test_arquivo_pequeno_demais_e_recusado() -> None:
    """Uma fotografia de escorpião utilizável não cabe em 8 KB."""
    r = validate(b"\xff\xd8\xff" + b"\x00" * 100)
    assert r.reason is RejectionCode.TOO_SMALL


def test_arquivo_grande_demais_e_recusado() -> None:
    r = validate(b"\xff\xd8\xff" + b"\x00" * MAX_BYTES)
    assert r.reason is RejectionCode.TOO_LARGE


def test_o_piso_de_bytes_bate_com_o_do_flutter() -> None:
    """Os três lugares que guardam estes números precisam concordar.

    `ImageLimits` no Flutter, a regra do Storage e este módulo. A duplicação é
    deliberada — cada camada valida por sua conta —, e sair de sincronia é o
    risco que este teste cobre.
    """
    assert MIN_BYTES == 8 * 1024
    assert MAX_BYTES == 8 * 1024 * 1024


# -- Dimensões -----------------------------------------------------------------


def test_imagem_de_dimensao_pequena_demais_e_recusada() -> None:
    """Abaixo de 480px os caracteres que distinguem as espécies não estão lá.

    Aceitar seria prometer uma análise impossível.
    """
    r = validate(jpeg(400, 300))

    assert not r.ok
    assert r.reason is RejectionCode.DIMENSIONS_TOO_SMALL
    assert (r.width, r.height) == (400, 300)


def test_imagem_gigante_e_recusada_antes_de_decodificar() -> None:
    """Uma imagem de 8000px em RGBA ocupa ~256 MB de heap.

    Em aparelho modesto isso é o encerramento do processo, não uma exceção que
    dê para tratar. Por isso a recusa olha o cabeçalho, e não o resultado da
    decodificação.
    """
    r = validate(png(8000, 6000))

    assert not r.ok
    assert r.reason is RejectionCode.DIMENSIONS_TOO_LARGE


def test_dimensao_ilegivel_e_recusada() -> None:
    """Cabeçalho que diz ser PNG mas não traz IHDR utilizável."""
    quebrado = _encher(b"\x89PNG\r\n\x1a\n" + b"\x00" * 16)

    r = validate(quebrado)

    assert not r.ok
    assert r.reason is RejectionCode.DIMENSIONS_UNREADABLE


def test_dimensao_no_limite_exato_passa() -> None:
    """Os limites são inclusivos.

    Uma foto de exatamente 480px no menor lado é aceitável; recusá-la por um
    pixel seria arbitrário.
    """
    assert validate(jpeg(640, 480)).ok
    assert validate(png(6000, 4000)).ok
