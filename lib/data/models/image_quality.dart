import 'package:flutter/foundation.dart';

/// Veredito de qualidade fotográfica (briefing Fase 4, §5).
enum ImageQuality {
  /// Boa o bastante para a análise sem ressalva.
  good,

  /// Serve, mas com alguma limitação que vale avisar.
  acceptable,

  /// Provavelmente vai atrapalhar. O usuário decide se segue mesmo assim.
  poor,

  /// Inutilizável — quadro preto, estourado ou chapado. Bloqueia o pipeline.
  invalid,
}

/// O que há de errado com a foto.
///
/// Um aviso não é um erro: ele existe para virar uma frase acionável na tela
/// ("essa foto está muito escura"), que foi o que o §6 pediu no lugar de um
/// erro genérico.
enum ImageQualityWarning {
  tooDark,
  tooBright,
  lowContrast,
  blurry,
  softFocus,
  lowResolution;

  /// Frase para o usuário, já dizendo o que fazer.
  String get message => switch (this) {
        ImageQualityWarning.tooDark =>
          'Essa foto está muito escura. Procure mais luz ou use a lanterna.',
        ImageQualityWarning.tooBright =>
          'A foto está estourada de luz. Evite fotografar contra o sol.',
        ImageQualityWarning.lowContrast =>
          'O animal quase não se separa do fundo. Tente outro ângulo.',
        ImageQualityWarning.blurry =>
          'A imagem parece desfocada. Apoie o celular e toque no animal para focar.',
        ImageQualityWarning.softFocus =>
          'O foco ficou um pouco mole. Se der, tire outra mais nítida.',
        ImageQualityWarning.lowResolution =>
          'Essa resolução pode dificultar a identificação. Aproxime-se do animal.',
      };
}

/// Medidas e veredito de uma fotografia.
///
/// # O que está aqui e o que ainda não está
/// Brilho, contraste, nitidez e resolução são medidas **da imagem inteira** —
/// dá para calculá-las sem saber o que a foto mostra.
///
/// Enquadramento, tamanho aparente do animal e obstrução, que o §5 também
/// pede, dependem de **saber onde o escorpião está**. Isso é trabalho do
/// `ScorpionDetectionService`, que só ganha modelo de verdade na Fase 5. Os
/// campos existem aqui, nulos, para que aquele dia seja preencher um valor e
/// não reabrir o modelo inteiro — e ficam nulos em vez de receberem um número
/// inventado, porque um placeholder numérico viraria decisão de produto sem
/// ninguém perceber.
@immutable
class ImageQualityResult {
  const ImageQualityResult({
    required this.quality,
    required this.score,
    required this.brightness,
    required this.contrast,
    required this.sharpness,
    required this.width,
    required this.height,
    this.warnings = const <ImageQualityWarning>[],
    this.subjectRatio,
    this.isSubjectCentered,
    this.isSubjectOccluded,
  });

  final ImageQuality quality;

  /// Nota agregada de 0 a 1. Serve para ordenar e comparar; o veredito
  /// acionável é [quality].
  final double score;

  /// Luminância média, de 0 (preto) a 1 (branco).
  final double brightness;

  /// Desvio padrão da luminância. Perto de zero é quadro chapado.
  final double contrast;

  /// Variância do laplaciano normalizada. Quanto maior, mais nítida.
  final double sharpness;

  final int width;
  final int height;

  final List<ImageQualityWarning> warnings;

  /// Fração do quadro ocupada pelo animal. **Fase 5.**
  final double? subjectRatio;

  /// Se o animal está dentro da área central segura. **Fase 5.**
  final bool? isSubjectCentered;

  /// Se parte do animal está cortada ou escondida. **Fase 5.**
  final bool? isSubjectOccluded;

  /// Megapixels, para exibição e registro.
  double get megapixels => (width * height) / 1000000;

  bool get isUsable => quality != ImageQuality.invalid;

  /// Se o usuário deve ser consultado antes de seguir.
  bool get shouldWarnUser =>
      quality == ImageQuality.poor || warnings.isNotEmpty;

  /// Forma persistida em `identifications/{id}.imageQuality`.
  ///
  /// Guardamos as medidas, não só o veredito: quando os limiares forem
  /// recalibrados na Fase 6, dá para reavaliar o que já foi coletado sem
  /// pedir foto nova a ninguém.
  Map<String, Object?> toMap() => <String, Object?>{
        'quality': quality.name,
        'score': double.parse(score.toStringAsFixed(4)),
        'brightness': double.parse(brightness.toStringAsFixed(4)),
        'contrast': double.parse(contrast.toStringAsFixed(4)),
        'sharpness': double.parse(sharpness.toStringAsFixed(5)),
        'width': width,
        'height': height,
        'warnings': warnings
            .map((ImageQualityWarning w) => w.name)
            .toList(growable: false),
      };

  @override
  String toString() => 'ImageQualityResult(${quality.name}, '
      'score ${score.toStringAsFixed(2)}, ${width}x$height)';
}
