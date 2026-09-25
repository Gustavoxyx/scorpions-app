
import 'package:flutter/foundation.dart';

import 'image_quality.dart';
import 'image_validation.dart';

/// Uma das três formas em que a imagem existe depois do processamento (§7).
@immutable
class ImageVariant {
  const ImageVariant({
    required this.bytes,
    required this.width,
    required this.height,
    required this.format,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final ImageFormat format;

  int get byteCount => bytes.length;

  @override
  String toString() =>
      'ImageVariant(${width}x$height, ${format.extension}, $byteCount B)';
}

/// As três formas, juntas.
///
/// A separação é conceitual e proposital (§7 e §22):
///
/// - **original** — o registro. Metadados removidos, pixels preservados.
///   É dele que um modelo melhor vai querer reprocessar no futuro.
/// - **processed** — o que a análise consome. Reduzido, orientado, padronizado.
/// - **thumbnail** — o que as listas exibem. Existe para que abrir o histórico
///   não baixe megabytes.
@immutable
class ProcessedImage {
  const ProcessedImage({
    required this.original,
    required this.processed,
    required this.thumbnail,
    required this.originalWasReencoded,
  });

  final ImageVariant original;
  final ImageVariant processed;
  final ImageVariant thumbnail;

  /// Se o original teve de ser recomprimido.
  ///
  /// Acontece só quando a foto trazia etiqueta de orientação: apagar os
  /// metadados sem reencodar deixaria a imagem deitada em qualquer visualizador.
  /// Registrar isso importa porque diz se aquele arquivo é o pixel original do
  /// sensor ou uma segunda geração.
  final bool originalWasReencoded;

  int get totalBytes =>
      original.byteCount + processed.byteCount + thumbnail.byteCount;
}

/// Tudo que se sabe sobre a imagem antes de decidir o que fazer com ela.
///
/// Um objeto só porque as três etapas — validar, medir e derivar — acontecem
/// numa passada única, dentro do mesmo isolate. Decodificar uma foto de 12 MP
/// é o gasto dominante do pipeline; fazer isso uma vez em vez de três é a
/// diferença entre o aplicativo responder e travar num aparelho de entrada.
@immutable
class ImagePreparation {
  const ImagePreparation({
    required this.validation,
    this.quality,
    this.image,
  });

  /// Recusa na porta: nem qualidade nem processamento chegaram a acontecer.
  factory ImagePreparation.rejected(ImageValidationResult validation) {
    assert(!validation.isValid, 'Recusa exige uma validação que falhou.');
    return ImagePreparation(validation: validation);
  }

  final ImageValidationResult validation;

  /// Nulo quando a validação recusou a imagem.
  final ImageQualityResult? quality;

  /// Nulo quando a validação recusou a imagem.
  final ProcessedImage? image;

  bool get isValid => validation.isValid;

  /// Se o pipeline pode seguir. Qualidade `invalid` interrompe; `poor` não —
  /// essa é decisão do usuário (§6).
  bool get canProceed => isValid && (quality?.isUsable ?? false);
}
