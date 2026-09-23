import 'dart:math';

import '../../core/constants/app_config.dart';
import '../models/captured_image.dart';
import '../models/identification.dart';
import '../models/species.dart';
import '../mock/mock_species.dart';

/// Contrato do motor de identificação.
///
///     CapturedImage -> IdentificationService -> IdentificationResult
///
/// É a fronteira que protege toda a interface da troca de tecnologia. Na Fase 5
/// entram implementações reais (`TfliteIdentificationService`,
/// `RemoteIdentificationService`) sem que nenhuma tela mude, porque a UI só
/// conhece este contrato e o modelo de resultado.
abstract interface class IdentificationService {
  /// Executa a identificação.
  ///
  /// [onStage] recebe o índice do estágio corrente (0..n-1) para que a tela de
  /// análise reflita o progresso real quando ele existir.
  Future<IdentificationResult> identify(
    CapturedImage image, {
    void Function(int stageIndex)? onStage,
    int stageCount,
  });
}

/// FASE 1 — implementação simulada.
///
/// Sorteia um desfecho com pesos que imitam a realidade de um classificador
/// honesto: a maior parte acerta com confiança alta, uma fatia fica em
/// confiança média/baixa e uma fatia relevante é REJEITADA. O objetivo é que o
/// fluxo de "não sei" seja exercitado com frequência, não escondido.
class MockIdentificationService implements IdentificationService {
  MockIdentificationService({Random? random, this.delay})
      : _random = random ?? Random();

  final Random _random;

  /// Sobrescreve a duração simulada (usado por testes).
  final Duration? delay;

  @override
  Future<IdentificationResult> identify(
    CapturedImage image, {
    void Function(int stageIndex)? onStage,
    int stageCount = 4,
  }) async {
    final Duration total = delay ?? AppConfig.mockAnalysisDuration;
    final Duration perStage =
        Duration(microseconds: total.inMicroseconds ~/ stageCount);

    for (int i = 0; i < stageCount; i++) {
      onStage?.call(i);
      await Future<void>.delayed(perStage);
    }

    final String id = 'mock-${DateTime.now().microsecondsSinceEpoch}';
    final double roll = _random.nextDouble();

    // 18% das análises terminam sem resposta. Isso é intencional.
    if (roll < 0.18) {
      const List<RejectionReason> reasons = RejectionReason.values;
      return IdentificationResult.rejected(
        id: id,
        image: image,
        isMock: true,
        reason: reasons[_random.nextInt(reasons.length)],
      );
    }

    final double topScore = switch (roll) {
      < 0.62 => 0.86 + _random.nextDouble() * 0.12, // alta
      < 0.85 => 0.66 + _random.nextDouble() * 0.18, // média
      _ => 0.47 + _random.nextDouble() * 0.17, // baixa
    };

    final List<Species> pool = List<Species>.of(MockSpecies.all)
      ..shuffle(_random);
    final double secondScore = (1 - topScore) * (0.4 + _random.nextDouble() * 0.4);

    return IdentificationResult.identified(
      id: id,
      image: image,
      isMock: true,
      predictions: <SpeciesPrediction>[
        SpeciesPrediction(species: pool[0], score: topScore),
        SpeciesPrediction(species: pool[1], score: secondScore),
        SpeciesPrediction(
          species: pool[2],
          score: (1 - topScore - secondScore).clamp(0.01, 1),
        ),
      ],
    );
  }
}
