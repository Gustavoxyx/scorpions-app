import 'package:flutter_test/flutter_test.dart';
import 'package:scorpions/core/constants/decision_thresholds.dart';
import 'package:scorpions/data/models/capture_instruction.dart';
import 'package:scorpions/data/models/classification.dart';
import 'package:scorpions/data/models/image_quality.dart';
import 'package:scorpions/data/models/view_prediction.dart';
import 'package:scorpions/data/services/confidence_engine.dart';
import 'package:scorpions/data/services/multi_view_fusion_service.dart';

/// Testes da decisão.
///
/// Cada caso aqui é uma situação que o sistema vai encontrar de verdade, e a
/// pergunta é sempre a mesma: ele reconhece quando **não sabe**? Um
/// classificador que sempre responde é fácil; o difícil — e o que o briefing
/// pede em §12, §14 e §17 — é recusar no momento certo.
void main() {
  const ConfidenceEngine motor = ConfidenceEngine();
  const LateFusionService fusao = LateFusionService();

  ViewPrediction vista(CaptureType tipo, Map<String, double> scores) {
    final List<MapEntry<String, double>> ordenado = scores.entries.toList()
      ..sort((MapEntry<String, double> a, MapEntry<String, double> b) =>
          b.value.compareTo(a.value));
    return ViewPrediction(
      captureType: tipo,
      modelVersion: 'teste-v1',
      candidates: ordenado
          .map((MapEntry<String, double> e) => SpeciesCandidate(
                speciesId: e.key,
                scientificName: e.key,
                confidence: e.value,
              ))
          .toList(growable: false),
    );
  }

  ConfidenceAssessment avaliar(
    List<Map<String, double>> vistas, {
    ImageQuality? qualidade,
    FusionStrategy estrategia = FusionStrategy.average,
  }) {
    final List<ViewPrediction> ps = <ViewPrediction>[
      for (int i = 0; i < vistas.length; i++)
        vista(i == 0 ? CaptureType.topView : CaptureType.tail, vistas[i]),
    ];
    return motor.assess(
      fusao.fuse(ps, strategy: estrategia),
      combinedQuality: qualidade,
    );
  }

  group('rejeição (§17)', () {
    test('nenhuma hipótese acima do piso vira rejeição, não um palpite', () {
      final ConfidenceAssessment a = avaliar(<Map<String, double>>[
        <String, double>{'x': 0.30, 'y': 0.25, 'z': 0.23, 'w': 0.22},
      ]);

      expect(a.level, DecisionLevel.reject);
      expect(a.primaryReason, DecisionReason.scoreBelowRejection);
      expect(a.level.showsSpecies, isFalse,
          reason: 'dizer uma espécie errada sobre animal peçonhento é pior '
              'que dizer "não sei"');
    });

    test('rejeição vem antes de qualquer outra consideração', () {
      // Score baixo E vistas em conflito. A rejeição não depende de ponderar
      // nada: se nada alcança o piso, não há o que ponderar.
      final ConfidenceAssessment a = avaliar(<Map<String, double>>[
        <String, double>{'x': 0.30, 'y': 0.28},
        <String, double>{'y': 0.31, 'x': 0.29},
      ]);

      expect(a.level, DecisionLevel.reject);
    });

    // REGRESSÃO — este caso já quebrou uma vez, antes de existir modelo.
    //
    // A fusão renormaliza os candidatos para somarem 1, porque é isso que a
    // tela precisa mostrar. Só que a soma dos scores listados é menor que 1,
    // e reescalar INFLA: duas hipóteses em 0,295 viram 0,50 cada. Um modelo
    // que não sustentou nada passava a aparentar meia certeza, e o limiar de
    // rejeição nunca disparava — exatamente no caso em que ele mais importa.
    //
    // A correção foi separar as duas coisas: os candidatos saem
    // renormalizados, e `rawTopScore` guarda o valor cru para a decisão.
    test('probabilidade espalhada é rejeitada, mesmo depois da renormalização',
        () {
      final List<ViewPrediction> ps = <ViewPrediction>[
        vista(CaptureType.topView, <String, double>{'x': 0.30, 'y': 0.28}),
        vista(CaptureType.tail, <String, double>{'y': 0.31, 'x': 0.29}),
      ];
      final FusedPrediction f = fusao.fuse(ps, strategy: FusionStrategy.average);

      expect(f.rawTopScore, closeTo(0.295, 1e-9),
          reason: 'o que o modelo realmente devolveu');
      expect(f.top!.confidence, closeTo(0.5, 1e-9),
          reason: 'o que a tela mostra, depois de somar 1');
      expect(f.rawTopScore, lessThan(DecisionThresholds.rejectBelow));

      expect(motor.assess(f).level, DecisionLevel.reject,
          reason: 'a decisão precisa olhar o valor cru; olhar o reescalado '
              'afirmaria uma espécie que o modelo não sustentou');
    });
  });

  group('revisão humana (§14, §18)', () {
    test('empate entre primeiro e segundo vai para especialista', () {
      final ConfidenceAssessment a = avaliar(<Map<String, double>>[
        <String, double>{'x': 0.51, 'y': 0.49},
      ]);

      expect(a.level, DecisionLevel.humanReview);
      expect(a.reasons, contains(DecisionReason.marginAmbiguous));
      expect(a.needsHumanReview, isTrue);
    });

    test('vistas apontando espécies sem hipóteses em comum', () {
      final ConfidenceAssessment a = avaliar(<Map<String, double>>[
        <String, double>{'x': 0.95, 'y': 0.05},
        <String, double>{'w': 0.95, 'z': 0.05},
      ]);

      expect(a.level, DecisionLevel.humanReview);
      expect(a.reasons, contains(DecisionReason.viewsConflict));
    });

    test('score alto não compra uma decisão quando as vistas se contradizem',
        () {
      // Cada vista tem convicção alta — em espécies diferentes. Um sistema
      // que olhasse só o score da fusão poderia apresentar isto como
      // resultado. É o erro que o §14 manda não cometer.
      final ConfidenceAssessment a = avaliar(<Map<String, double>>[
        <String, double>{'x': 0.98, 'y': 0.02},
        <String, double>{'z': 0.98, 'w': 0.02},
      ]);

      expect(a.level, DecisionLevel.humanReview);
      expect(a.level.showsSpecies, isFalse);
    });
  });

  group('graus de confiança', () {
    test('vencedor folgado, vistas de acordo, imagem boa', () {
      final ConfidenceAssessment a = avaliar(
        <Map<String, double>>[
          <String, double>{'x': 0.90, 'y': 0.07, 'z': 0.03},
          <String, double>{'x': 0.88, 'y': 0.08, 'z': 0.04},
        ],
        qualidade: ImageQuality.good,
      );

      expect(a.level, DecisionLevel.highConfidence);
      expect(a.usedBothViews, isTrue);
      expect(a.score, greaterThan(DecisionThresholds.highScore));
    });

    test('uma foto só nunca alcança confiança alta', () {
      final ConfidenceAssessment a = avaliar(
        <Map<String, double>>[
          <String, double>{'x': 0.95, 'y': 0.03, 'z': 0.02},
        ],
        qualidade: ImageQuality.good,
      );

      expect(a.level, DecisionLevel.mediumConfidence);
      expect(a.reasons, contains(DecisionReason.singleViewOnly));
      expect(a.usedBothViews, isFalse);
    });

    test('imagem ruim rebaixa mesmo com o modelo convicto', () {
      final ConfidenceAssessment boa = avaliar(
        <Map<String, double>>[
          <String, double>{'x': 0.88, 'y': 0.08, 'z': 0.04},
          <String, double>{'x': 0.86, 'y': 0.09, 'z': 0.05},
        ],
        qualidade: ImageQuality.good,
      );
      final ConfidenceAssessment ruim = avaliar(
        <Map<String, double>>[
          <String, double>{'x': 0.88, 'y': 0.08, 'z': 0.04},
          <String, double>{'x': 0.86, 'y': 0.09, 'z': 0.05},
        ],
        qualidade: ImageQuality.poor,
      );

      expect(boa.level, DecisionLevel.highConfidence);
      expect(ruim.level.index, greaterThan(boa.level.index),
          reason: 'o modelo responde com a mesma firmeza sobre foto borrada; '
              'quem sabe que ela está ruim é o pipeline');
      expect(ruim.reasons, contains(DecisionReason.poorImageQuality));
    });

    test('margem apertada rebaixa mesmo com score aceitável', () {
      final ConfidenceAssessment a = avaliar(
        <Map<String, double>>[
          <String, double>{'x': 0.55, 'y': 0.42, 'z': 0.03},
          <String, double>{'x': 0.54, 'y': 0.43, 'z': 0.03},
        ],
        qualidade: ImageQuality.good,
      );

      expect(a.level.showsSpecies, isTrue);
      expect(a.level, isNot(DecisionLevel.highConfidence));
      expect(a.reasons, contains(DecisionReason.marginNarrow));
    });
  });

  group('honestidade do número (§16, §28)', () {
    test('toda avaliação declara que os limiares não foram calibrados', () {
      final ConfidenceAssessment a = avaliar(<Map<String, double>>[
        <String, double>{'x': 0.90, 'y': 0.10},
      ]);

      expect(a.thresholdsCalibrated, isFalse);
      expect(a.reasons, contains(DecisionReason.uncalibratedThresholds),
          reason: 'enquanto não houver conjunto de validação, isso é parte do '
              'resultado — não nota de rodapé');
    });

    test('sem modelo, nada é avaliado e nada é inventado', () {
      final ConfidenceAssessment a =
          motor.assess(const FusedPrediction.notEvaluated());

      expect(a.primaryReason, DecisionReason.notEvaluated);
      expect(a.level.showsSpecies, isFalse);
      expect(a.score, 0);
    });
  });

  group('peso por qualidade', () {
    test('cada medida tem o seu peso, e imagem inutilizável tem o menor', () {
      expect(ConfidenceEngine.weightFor(ImageQuality.good),
          DecisionThresholds.goodQualityWeight);
      expect(ConfidenceEngine.weightFor(ImageQuality.acceptable),
          DecisionThresholds.acceptableQualityWeight);
      expect(ConfidenceEngine.weightFor(ImageQuality.poor),
          DecisionThresholds.poorQualityWeight);
      expect(ConfidenceEngine.weightFor(ImageQuality.invalid),
          DecisionThresholds.poorQualityWeight);
    });

    test('qualidade desconhecida não penaliza', () {
      // Imagem simulada não tem pixels para medir. Penalizá-la quebraria o
      // modo de demonstração sem proteger ninguém.
      expect(ConfidenceEngine.weightFor(null),
          DecisionThresholds.goodQualityWeight);
    });
  });
}
