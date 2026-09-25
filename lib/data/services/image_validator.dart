import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../core/constants/image_limits.dart';
import '../models/image_validation.dart';

/// Primeira barreira do pipeline (briefing Fase 4, §4).
///
/// # O que ela decide
/// Se vale a pena gastar CPU, memória e rede com esta imagem. Nada além disso.
/// Qualidade fotográfica é outra pergunta, respondida pelo
/// `ImageQualityService` — misturar as duas produziria um veredito único e
/// inútil ("imagem ruim") para causas que exigem ações diferentes do usuário.
///
/// # Por que a assinatura binária e não a extensão
/// Extensão e `contentType` são escolhidos por quem envia e podem mentir. Um
/// executável renomeado para `.jpg` passa em qualquer conferência de nome. Os
/// primeiros bytes do arquivo, não. Isso barra o descuidado e encarece a vida
/// do mal-intencionado — mas **não substitui as Storage Rules**, que são a
/// autoridade de verdade.
///
/// # Custo
/// A leitura de dimensões usa `startDecode`, que interpreta apenas o cabeçalho.
/// Uma imagem de 12 MP é medida sem alocar os 48 MB que a decodificação
/// completa custaria.
class ImageValidator {
  const ImageValidator();

  ImageValidationResult validate(Uint8List bytes) {
    if (bytes.isEmpty) {
      return ImageValidationResult.rejected(ImageValidationCode.empty);
    }
    if (bytes.length < ImageLimits.minBytes) {
      return ImageValidationResult.rejected(
        ImageValidationCode.tooSmall,
        byteCount: bytes.length,
      );
    }
    if (bytes.length > ImageLimits.maxBytes) {
      return ImageValidationResult.rejected(
        ImageValidationCode.tooLarge,
        byteCount: bytes.length,
      );
    }

    final ImageFormat? format = detectFormat(bytes);
    if (format == null) {
      return ImageValidationResult.rejected(
        _looksLikeKnownButUnsupportedImage(bytes)
            ? ImageValidationCode.unsupported
            : ImageValidationCode.invalidFormat,
        byteCount: bytes.length,
      );
    }

    final img.DecodeInfo? info = _readHeader(bytes);
    if (info == null || info.width <= 0 || info.height <= 0) {
      return ImageValidationResult.rejected(
        ImageValidationCode.corrupted,
        format: format,
        byteCount: bytes.length,
      );
    }

    final int shortest = info.width < info.height ? info.width : info.height;
    final int longest = info.width > info.height ? info.width : info.height;

    if (shortest < ImageLimits.minDimension) {
      return ImageValidationResult.rejected(
        ImageValidationCode.tooFewPixels,
        format: format,
        width: info.width,
        height: info.height,
        byteCount: bytes.length,
      );
    }
    if (longest > ImageLimits.maxDimension) {
      return ImageValidationResult.rejected(
        ImageValidationCode.tooManyPixels,
        format: format,
        width: info.width,
        height: info.height,
        byteCount: bytes.length,
      );
    }

    return ImageValidationResult.valid(
      format: format,
      width: info.width,
      height: info.height,
      byteCount: bytes.length,
    );
  }

  /// Formato pelos "números mágicos" do início do arquivo.
  ///
  /// JPEG: `FF D8 FF` · PNG: `89 50 4E 47` · WebP: `RIFF` + `WEBP` no byte 8.
  static ImageFormat? detectFormat(Uint8List b) {
    if (b.length < 12) return null;

    if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return ImageFormat.jpeg;

    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return ImageFormat.png;
    }

    final bool riff =
        b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46;
    final bool webp =
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50;
    if (riff && webp) return ImageFormat.webp;

    return null;
  }

  /// Separa "não é imagem" de "é imagem, mas não tratamos esse formato".
  ///
  /// A distinção importa para o usuário: um GIF merece "use JPG ou PNG"; um
  /// PDF merece "isso não é uma imagem".
  static bool _looksLikeKnownButUnsupportedImage(Uint8List b) {
    if (b.length < 4) return false;

    // GIF87a / GIF89a
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return true;
    // BMP
    if (b[0] == 0x42 && b[1] == 0x4D) return true;
    // TIFF little-endian (II*.) e big-endian (MM.*)
    if (b[0] == 0x49 && b[1] == 0x49 && b[2] == 0x2A) return true;
    if (b[0] == 0x4D && b[1] == 0x4D && b[2] == 0x00 && b[3] == 0x2A) {
      return true;
    }
    // HEIC/HEIF: caixa `ftyp` na posição 4.
    if (b.length >= 12 &&
        b[4] == 0x66 &&
        b[5] == 0x74 &&
        b[6] == 0x79 &&
        b[7] == 0x70) {
      return true;
    }
    return false;
  }

  /// Lê largura e altura sem decodificar os pixels.
  static img.DecodeInfo? _readHeader(Uint8List bytes) {
    try {
      return img.findDecoderForData(bytes)?.startDecode(bytes);
    } catch (_) {
      // Cabeçalho inconsistente: tratamos como corrompido, não como exceção.
      return null;
    }
  }
}
