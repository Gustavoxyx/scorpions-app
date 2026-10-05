import 'package:flutter/foundation.dart';

import '../../core/constants/decision_thresholds.dart';
import '../models/image_quality.dart';
import 'multi_view_fusion_service.dart';

/// O que fazer com a predição (§15).
enum DecisionLevel {
  /// Mostrar o resultado.
  highConfidence('high_confidence'),

  /// Mostrar com ressalva, e oferecer uma foto adicional.
  mediumConfidence('medium_confidence'),

  /// Não apresentar como identificação. Oferecer caminhos.
  lowConfidence('low_confidence'),

  /// Nenhuma hipótese é aceitável — §17.
  reject('reject'),

  /// Encaminhar a um especialista — §18.
  humanReview('human_review');

  const DecisionLevel(this.id);

  final String id;

  bool get showsSpecies =>
      this == DecisionLevel.highConfidence || this == DecisionLevel.mediumConfidence;
}

/// Por que a decisão foi essa.
///
/// # Por que isto existe
/// Três razões, e nenhuma é cosmética. O §19 exige que o item da fila de
/// revisão diga ao especialista **por que** chegou até ele. O §39 exige poder
/// reconstruir a decisão depois. E a tela precisa de algo honesto para
/// escrever — "confiança baixa" não ajuda ninguém, enquanto "as duas fotos
/// discordaram" diz à pessoa o que fazer a seguir.
enum DecisionReason {
  scoreBelowRejection('score_below_rejection'),
  scoreLow('score_low'),
  marginAmbiguous('margin_ambiguous'),
  marginNarrow('margin_narrow'),
  viewsConflict('views_conflict'),
  viewsDisagree('views_disagree'),
  poorImageQuality('poor_image_quality'),
  singleViewOnly('single_view_only'),
  notEvaluated('not_evaluated'),
  uncalibratedThresholds('uncalibrated_thresholds');

  const DecisionReason(this.id);

  final String id;

  /// Frase para o especialista, não para o usuário final.
  String get explanation => switch (this) {
        DecisionReason.scoreBelowRejection =>
          'Nenhuma espécie do catálogo recebeu pontuação suficiente.',
        DecisionReason.scoreLow => 'A hipótese vencedora teve pontuação baixa.',
        DecisionReason.marginAmbiguous =>
          'Primeira e segunda hipóteses praticamente empatadas.',
        DecisionReason.marginNarrow =>
          'A diferença entre as duas primeiras hipóteses é pequena.',
        DecisionReason.viewsConflict =>
          'As duas fotos apontaram espécies diferentes e consideraram '
              'hipóteses distintas.',
        DecisionReason.viewsDisagree =>
          'As duas fotos divergiram na distribuição de hipóteses.',
        DecisionReason.poorImageQuality =>
          'A qualidade das imagens limita a confiabilidade da análise.',
        DecisionReason.singleViewOnly =>
          'A análise usou apenas uma fotografia.',
        DecisionReason.notEvaluated => 'Nenhum modelo avaliou estas imagens.',
        DecisionReason.uncalibratedThresholds =>
          'Os limiares de decisão ainda não foram calibrados em conjunto de '
              'validação.',
      };
}

/// A decisão, com o rastro de como foi tomada.
@immutable
class ConfidenceAssessment {
  const ConfidenceAssessment({
    required this.level,
    required this.reasons,
    required this.score,
    required this.margin,
    required this.viewAgreement,
    required this.viewCount,
    required this.thresholdsCalibrated,
  });

  const ConfidenceAssessment.notEvaluated()
      : level = DecisionLevel.lowConfidence,
        reasons = const <DecisionReason>[DecisionReason.notEvaluated],
        score = 0,
        margin = 0,
        viewAgreement = 0,
        viewCount = 0,
        thresholdsCalibrated = false;

  final DecisionLevel level;

  /// Ordenadas da razão mais determinante para a menos. A primeira é a que
  /// decidiu; as outras são contexto.
  final List<DecisionReason> reasons;

  final double score;
  final double margin;
  final double viewAgreement;
  final int viewCount;

  /// Se os limiares usados passaram por conjunto de validação.
  ///
  /// Enquanto for `false`, nenhum número desta classe pode ser apresentado
  /// como probabilidade (§16, §28).
  final bool thresholdsCalibrated;

  bool get needsHumanReview => level == DecisionLevel.humanReview;
  bool get usedBothViews => viewCount >= 2;

  DecisionReason? get primaryReason =>
      reasons.isEmpty ? null : reasons.first;

  Map<String, Object?> toMap() => <String, Object?>{
        'level': level.id,
        'reasons': reasons.map((DecisionReason r) => r.id).toList(growable: false),
        'score': double.parse(score.toStringAsFixed(4)),
        'margin': double.parse(margin.toStringAsFixed(4)),
        'viewAgreement': double.parse(viewAgreement.toStringAsFixed(4)),
        'viewCount': viewCount,
        'thresholdsCalibrated': thresholdsCalibrated,
      };
}

/// Decide o que fazer com a predição fundida (§12).
///
/// # Onde ele fica
/// Entre o modelo e a decisão, nunca dentro da tela. A interface recebe um
/// [DecisionLevel] pronto e desenha; ela não conhece limiar nenhum. Sem essa
/// separação, calibrar o sistema viraria editar widgets, e dois widgets
/// acabariam com limiares diferentes para a mesma pergunta.
///
/// # Por que não basta olhar o score
/// Porque o score sozinho mente em três situações que este sistema vai
/// encontrar o tempo todo:
///
/// 1. **Empate com aparência de vitória.** 0,80 contra 0,78 tem score alto e
///    não é identificação nenhuma.
/// 2. **Vistas em desacordo.** Cada foto apontando uma espécie, e a fusão
///    produzindo um vencedor confortável que nenhuma das duas sustenta.
/// 3. **Confiança sobre imagem ruim.** O modelo não sabe que a foto está
///    borrada; ele responde com a mesma firmeza de sempre.
///
/// Por isso a decisão olha score, margem, acordo entre vistas e qualidade — e
/// a mais restritiva vence.
class ConfidenceEngine {
  const ConfidenceEngine();

  /// Converte a medida de qualidade no peso que aquela vista terá na fusão.
  static double weightFor(ImageQuality? quality) => switch (quality) {
        ImageQuality.good => DecisionThresholds.goodQualityWeight,
        ImageQuality.acceptable => DecisionThresholds.acceptableQualityWeight,
        ImageQuality.poor => DecisionThresholds.poorQualityWeight,
        // Imagem inutilizável não chega até aqui — o pipeline barra antes.
        // Se chegasse, o peso mínimo é mais seguro que um peso neutro.
        ImageQuality.invalid => DecisionThresholds.poorQualityWeight,
        null => DecisionThresholds.goodQualityWeight,
      };

  ConfidenceAssessment assess(
    FusedPrediction prediction, {
    ImageQuality? combinedQuality,
  }) {
    if (!prediction.wasEvaluated) {
      return const ConfidenceAssessment.notEvaluated();
    }

    final double score = prediction.top!.confidence;
    final double margin = prediction.margin;
    final double acordo = prediction.consistency.distributionAgreement;

    final List<DecisionReason> razoes = <DecisionReason>[];

    // -- Rejeição ------------------------------------------------------------
    // Vem primeiro porque é a única conclusão que não depende de mais nada:
    // se nenhuma hipótese alcança o piso, não há o que ponderar.
    //
    // Olha o score CRU, não o renormalizado, e a diferença não é detalhe.
    // Reescalar os candidatos para somarem 1 infla um modelo indeciso: um
    // par de hipóteses em 0,295 vira 0,50 cada, e o limiar de rejeição
    // deixaria de disparar justamente no caso em que mais precisa — aquele
    // em que o modelo espalhou a probabilidade e não sustentou nada.
    if (prediction.rawTopScore < DecisionThresholds.rejectBelow) {
      return _montar(
        DecisionLevel.reject,
        <DecisionReason>[DecisionReason.scoreBelowRejection],
        prediction,
        score,
        margin,
        acordo,
      );
    }

    // -- Revisão humana ------------------------------------------------------
    // Dois casos, e os dois têm a mesma natureza: o sistema tem informação
    // suficiente para saber que **não sabe**. O §14 é explícito em não
    // escolher arbitrariamente quando há conflito.
    if (prediction.consistency.isConflicting ||
        (prediction.viewCount >= 2 &&
            acordo < DecisionThresholds.conflictingViews)) {
      razoes.add(DecisionReason.viewsConflict);
    }
    if (margin < DecisionThresholds.ambiguousMargin) {
      razoes.add(DecisionReason.marginAmbiguous);
    }
    if (razoes.isNotEmpty) {
      return _montar(
        DecisionLevel.humanReview,
        razoes,
        prediction,
        score,
        margin,
        acordo,
      );
    }

    // -- Graus de confiança --------------------------------------------------
    // A partir daqui a decisão é por acúmulo de ressalvas: cada condição que
    // falha rebaixa um nível. Preferido a uma fórmula com pesos porque é
    // auditável — o §39 pede reconstruir a decisão, e uma lista de ressalvas
    // se lê, enquanto uma soma ponderada precisa ser recalculada.
    if (score < DecisionThresholds.mediumScore) {
      razoes.add(DecisionReason.scoreLow);
    }
    if (margin < DecisionThresholds.decisiveMargin) {
      razoes.add(DecisionReason.marginNarrow);
    }
    if (prediction.viewCount >= 2 &&
        acordo < DecisionThresholds.consistentViews) {
      razoes.add(DecisionReason.viewsDisagree);
    }
    if (combinedQuality == ImageQuality.poor) {
      razoes.add(DecisionReason.poorImageQuality);
    }
    if (prediction.viewCount < 2) {
      razoes.add(DecisionReason.singleViewOnly);
    }

    final DecisionLevel nivel;
    if (razoes.isEmpty && score >= DecisionThresholds.highScore) {
      nivel = DecisionLevel.highConfidence;
    } else if (score >= DecisionThresholds.mediumScore && razoes.length <= 2) {
      nivel = DecisionLevel.mediumConfidence;
    } else {
      nivel = DecisionLevel.lowConfidence;
    }

    return _montar(nivel, razoes, prediction, score, margin, acordo);
  }

  static ConfidenceAssessment _montar(
    DecisionLevel nivel,
    List<DecisionReason> razoes,
    FusedPrediction prediction,
    double score,
    double margin,
    double acordo,
  ) {
    // Registrada em toda avaliação, e de propósito: enquanto os limiares não
    // passarem por um conjunto de validação, isso é parte do resultado, não
    // uma nota de rodapé. É o que impede a interface de apresentar o número
    // como se fosse medida.
    final List<DecisionReason> completas = <DecisionReason>[
      ...razoes,
      if (!DecisionThresholds.calibrated) DecisionReason.uncalibratedThresholds,
    ];

    return ConfidenceAssessment(
      level: nivel,
      reasons: completas,
      score: score,
      margin: margin,
      viewAgreement: acordo,
      viewCount: prediction.viewCount,
      thresholdsCalibrated: DecisionThresholds.calibrated,
    );
  }
}
