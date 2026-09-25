import 'package:flutter/foundation.dart';

/// Retângulo normalizado sobre a imagem, de 0 a 1.
///
/// Normalizado e não em pixels pelo mesmo motivo de [AnatomyHotspot]: a mesma
/// caixa precisa valer para o original, para a versão processada e para a
/// miniatura, que têm resoluções diferentes.
@immutable
class BoundingBox {
  const BoundingBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  /// Fração do quadro ocupada. É o número que responde "o animal aparece
  /// pequeno demais?" — a pergunta do §5 que a análise estatística não alcança.
  double get area => width * height;

  /// Distância do centro da caixa ao centro do quadro, de 0 a ~0,7.
  double get centerOffset {
    final double dx = (left + width / 2) - 0.5;
    final double dy = (top + height / 2) - 0.5;
    return (dx * dx + dy * dy) <= 0 ? 0 : (dx.abs() + dy.abs()) / 2;
  }

  /// Se a caixa encosta na borda — indício de animal cortado.
  bool get touchesEdge =>
      left <= 0.01 || top <= 0.01 || right >= 0.99 || bottom >= 0.99;

  Map<String, Object?> toMap() => <String, Object?>{
        'left': double.parse(left.toStringAsFixed(4)),
        'top': double.parse(top.toStringAsFixed(4)),
        'width': double.parse(width.toStringAsFixed(4)),
        'height': double.parse(height.toStringAsFixed(4)),
      };
}

/// Saída do detector: **há um escorpião nesta foto?**
///
/// # Por que detecção vem antes de classificação
/// Um classificador treinado em escorpiões responde "escorpião" para qualquer
/// coisa — inclusive para uma aranha, uma pedra ou um dedo. Ele foi treinado
/// para escolher entre espécies, não para dizer "isso não é um escorpião".
/// Perguntar primeiro se há um animal no quadro é o que impede o sistema de
/// afirmar com confiança alta uma espécie a partir de uma foto de parede.
@immutable
class ScorpionDetectionResult {
  const ScorpionDetectionResult({
    required this.isScorpion,
    required this.confidence,
    required this.modelVersion,
    required this.isMock,
    this.boundingBox,
  });

  /// Resposta honesta de quem ainda não tem modelo: "não sei".
  ///
  /// Confiança zero e [isScorpion] nulo. Não é `false` de propósito — negar
  /// seria uma afirmação tão inventada quanto confirmar.
  const ScorpionDetectionResult.unknown()
      : isScorpion = null,
        confidence = 0,
        modelVersion = mockVersion,
        isMock = true,
        boundingBox = null;

  /// Identificador da versão que produziu o resultado (§26).
  static const String mockVersion = 'mock-detection-v1';

  /// `null` significa **não avaliado**, não "não é escorpião".
  final bool? isScorpion;

  final double confidence;

  final BoundingBox? boundingBox;

  final String modelVersion;

  /// Se veio de uma implementação simulada. Enquanto for `true`, nenhuma tela
  /// pode apresentar este resultado como análise (§12).
  final bool isMock;

  bool get wasEvaluated => isScorpion != null;

  Map<String, Object?> toMap() => <String, Object?>{
        'isScorpion': isScorpion,
        'confidence': confidence,
        'modelVersion': modelVersion,
        'isMock': isMock,
        'boundingBox': boundingBox?.toMap(),
      };
}
