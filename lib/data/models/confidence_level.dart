import '../../core/constants/app_config.dart';

/// Faixas de confiança do produto.
///
/// Existe desde a Fase 1 porque a decisão de produto mais importante do app é
/// que ele PODE dizer "não sei". A UI trata as quatro faixas como estados de
/// primeira classe; a Fase 6 só troca quem calcula o valor.
enum ConfidenceLevel {
  high,
  medium,
  low,
  unidentified;

  /// Deriva a faixa a partir da probabilidade bruta do classificador.
  static ConfidenceLevel fromScore(double score) {
    if (score >= AppConfig.highConfidenceThreshold) return ConfidenceLevel.high;
    if (score >= AppConfig.mediumConfidenceThreshold) {
      return ConfidenceLevel.medium;
    }
    if (score >= AppConfig.rejectionThreshold) return ConfidenceLevel.low;
    return ConfidenceLevel.unidentified;
  }

  String get label => switch (this) {
        ConfidenceLevel.high => 'Alta confiança',
        ConfidenceLevel.medium => 'Confiança média',
        ConfidenceLevel.low => 'Baixa confiança',
        ConfidenceLevel.unidentified => 'Não identificado',
      };

  String get shortLabel => switch (this) {
        ConfidenceLevel.high => 'Alta',
        ConfidenceLevel.medium => 'Média',
        ConfidenceLevel.low => 'Baixa',
        ConfidenceLevel.unidentified => '—',
      };

  /// Frase de enquadramento honesto mostrada abaixo do resultado.
  String get guidance => switch (this) {
        ConfidenceLevel.high =>
          'As características observadas são consistentes com esta espécie. '
              'Ainda assim, trata-se de uma estimativa.',
        ConfidenceLevel.medium =>
          'A estimativa é plausível, mas há espécies semelhantes. Considere '
              'uma nova foto com mais detalhe da cauda e das pinças.',
        ConfidenceLevel.low =>
          'A evidência é fraca. Trate este resultado apenas como uma pista.',
        ConfidenceLevel.unidentified =>
          'O sistema preferiu não arriscar uma resposta.',
      };

  /// Se `false`, a tela de resultado positivo não deve ser exibida.
  bool get isPresentable => this != ConfidenceLevel.unidentified;
}
