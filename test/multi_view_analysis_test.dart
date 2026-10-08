import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scorpions/data/models/classification.dart';
import 'package:image/image.dart' as img;
import 'package:scorpions/core/constants/image_limits.dart';
import 'package:scorpions/data/models/capture_instruction.dart';
import 'package:scorpions/data/models/captured_image.dart';
import 'package:scorpions/data/models/identification_session.dart';
import 'package:scorpions/data/models/image_quality.dart';
import 'package:scorpions/data/models/processed_image.dart';
import 'package:scorpions/data/services/confidence_engine.dart';
import 'package:scorpions/data/services/image_processing_service.dart';
import 'package:scorpions/data/services/multi_view_analysis_service.dart';
import 'package:scorpions/data/services/species_classification_service.dart';

/// Integração da análise: sessão de duas vistas → detecção → classificação →
/// fusão → decisão.
///
/// Usa imagens sintéticas de verdade, processadas pelo pipeline real da Fase
/// 4. O que é substituído é só o classificador — porque ele ainda não existe.
void main() {
  late ProcessedImage imagemBoa;

  setUpAll(() {
    final ImagePreparation p =
        DefaultImageProcessingService.runPipeline(_foto());
    expect(p.isValid, isTrue, reason: 'a imagem de apoio precisa ser válida');
    imagemBoa = p.image!;
  });

  SessionView vista(
    ImageCaptureInstruction instrucao, {
    ProcessedImage? processada,
    ImageQuality medida = ImageQuality.good,
  }) {
    return SessionView(
      instruction: instrucao,
      image: CapturedImage(
        source: ImageSource.camera,
        capturedAt: DateTime(2026, 10, 5),
      ),
      processed: processada ?? imagemBoa,
      quality: _qualidade(medida),
    );
  }

  IdentificationSession sessao({
    SessionView? primeira,
    SessionView? segunda,
  }) {
    return IdentificationSession(
      id: 'sessao-teste',
      userId: 'uid-do-dono',
      primary: primeira ?? vista(ImageCaptureInstruction.primary),
      secondary: segunda,
      status: SessionStatus.processing,
      createdAt: DateTime(2026, 10, 5),
    );
  }

  group('sem modelo', () {
    test('nenhuma espécie é inventada — nem com duas fotos boas', () async {
      const MultiViewAnalysisService servico = MultiViewAnalysisService();

      final MultiViewAnalysis a = await servico.analyse(sessao(
        segunda: vista(ImageCaptureInstruction.tail),
      ));

      expect(a.wasEvaluated, isFalse);
      expect(a.fused.top, isNull);
      expect(a.assessment.level.showsSpecies, isFalse);
      expect(a.hasScorpion, isNull,
          reason: 'nulo, não falso: falso significaria "olhamos e não é"');
    });

    test('o classificador simulado devolve lista vazia, não sorteio', () async {
      const MockSpeciesClassificationService mock =
          MockSpeciesClassificationService();
      final List<String> vistos = <String>[];

      for (int i = 0; i < 20; i++) {
        final result = await mock.classify(imagemBoa);
        vistos.addAll(result.candidates.map((c) => c.speciesId));
      }

      expect(vistos, isEmpty,
          reason: 'vinte chamadas e nenhuma espécie: é a diferença entre '
              'ausência de modelo e modelo que chuta');
    });
  });

  group('duas vistas (§6, §9)', () {
    test('vistas concordantes produzem decisão apresentável', () async {
      final MultiViewAnalysisService servico = MultiViewAnalysisService(
        classifier: ScriptedClassificationService(<Map<String, double>>[
          <String, double>{'tityus-serrulatus': 0.90, 'tityus-bahiensis': 0.07},
          <String, double>{'tityus-serrulatus': 0.88, 'tityus-bahiensis': 0.09},
        ]),
      );

      final MultiViewAnalysis a = await servico.analyse(sessao(
        segunda: vista(ImageCaptureInstruction.tail),
      ));

      expect(a.wasEvaluated, isTrue);
      expect(a.fused.top!.speciesId, 'tityus-serrulatus');
      expect(a.assessment.level, DecisionLevel.highConfidence);
      expect(a.assessment.usedBothViews, isTrue);
      expect(a.viewPredictions.length, 2);
    });

    test('vistas conflitantes vão para revisão humana (§14, §18)', () async {
      final MultiViewAnalysisService servico = MultiViewAnalysisService(
        classifier: ScriptedClassificationService(<Map<String, double>>[
          <String, double>{'tityus-serrulatus': 0.95, 'tityus-bahiensis': 0.05},
          <String, double>{'bothriurus-bonariensis': 0.95, 'opisthacanthus-cayaporum': 0.05},
        ]),
      );

      final MultiViewAnalysis a = await servico.analyse(sessao(
        segunda: vista(ImageCaptureInstruction.tail),
      ));

      expect(a.assessment.level, DecisionLevel.humanReview);
      expect(a.assessment.reasons, contains(DecisionReason.viewsConflict));
      expect(a.assessment.level.showsSpecies, isFalse,
          reason: 'com as fotos se contradizendo, afirmar uma espécie seria '
              'escolher arbitrariamente — o §14 proíbe');
    });

    test('cada vista fica registrada em separado (§27, §39)', () async {
      final MultiViewAnalysisService servico = MultiViewAnalysisService(
        classifier: ScriptedClassificationService(<Map<String, double>>[
          <String, double>{'a': 0.80, 'b': 0.20},
          <String, double>{'a': 0.60, 'b': 0.40},
        ]),
      );

      final MultiViewAnalysis a = await servico.analyse(sessao(
        segunda: vista(ImageCaptureInstruction.tail),
      ));

      expect(a.viewPredictions[0].captureType, CaptureType.topView);
      expect(a.viewPredictions[1].captureType, CaptureType.tail);
      expect(a.viewPredictions[0].top!.confidence, greaterThan(
        a.viewPredictions[1].top!.confidence,
      ));
      // Sem isto, a contribuição de cada foto seria irrecuperável e a §27
      // ficaria impossível de responder depois.
      expect(a.toMap()['views'], hasLength(2));
    });

    test('qualidade ruim reduz o peso daquela vista', () async {
      final MultiViewAnalysisService servico = MultiViewAnalysisService(
        classifier: ScriptedClassificationService(<Map<String, double>>[
          <String, double>{'a': 0.80, 'b': 0.20},
          <String, double>{'b': 0.80, 'a': 0.20},
        ]),
      );

      final MultiViewAnalysis a = await servico.analyse(sessao(
        segunda: vista(ImageCaptureInstruction.tail, medida: ImageQuality.poor),
      ));

      expect(a.viewPredictions[1].qualityWeight, lessThan(
        a.viewPredictions[0].qualityWeight,
      ));
    });
  });

  group('uma vista só (§5)', () {
    test('a análise acontece, com ressalva registrada', () async {
      final MultiViewAnalysisService servico = MultiViewAnalysisService(
        classifier: ScriptedClassificationService(<Map<String, double>>[
          <String, double>{'a': 0.92, 'b': 0.05, 'c': 0.03},
        ]),
      );

      final MultiViewAnalysis a = await servico.analyse(sessao());

      expect(a.wasEvaluated, isTrue,
          reason: 'o animal pode ter fugido antes da segunda foto; recusar '
              'analisar puniria quem mais precisa da resposta');
      expect(a.assessment.reasons, contains(DecisionReason.singleViewOnly));
      expect(a.assessment.level, isNot(DecisionLevel.highConfidence));
    });

    test('vista sem imagem processada não entra na análise', () async {
      final SessionView semImagem = SessionView(
        instruction: ImageCaptureInstruction.tail,
        image: CapturedImage.simulated(),
      );
      final MultiViewAnalysisService servico = MultiViewAnalysisService(
        classifier: ScriptedClassificationService(<Map<String, double>>[
          <String, double>{'a': 0.90, 'b': 0.10},
        ]),
      );

      final MultiViewAnalysis a =
          await servico.analyse(sessao(segunda: semImagem));

      expect(a.viewPredictions.length, 1);
      expect(a.assessment.viewCount, 1);
    });
  });

  group('qualidade combinada (§5)', () {
    test('é a melhor das duas, não a média', () {
      final IdentificationSession s = sessao(
        primeira: vista(ImageCaptureInstruction.primary),
        segunda: vista(ImageCaptureInstruction.tail, medida: ImageQuality.poor),
      );

      expect(s.combinedQuality, ImageQuality.good,
          reason: 'a pergunta é se há informação suficiente para analisar, e '
              'uma vista boa responde sim mesmo ao lado de uma ruim');
    });

    test('duas ruins continuam ruins', () {
      final IdentificationSession s = sessao(
        primeira: vista(ImageCaptureInstruction.primary, medida: ImageQuality.poor),
        segunda: vista(ImageCaptureInstruction.tail, medida: ImageQuality.poor),
      );

      expect(s.combinedQuality, ImageQuality.poor);
    });

    test('sem medida nenhuma, não inventa uma', () {
      final IdentificationSession s = IdentificationSession(
        id: 'x',
        userId: 'u',
        primary: SessionView(
          instruction: ImageCaptureInstruction.primary,
          image: CapturedImage.simulated(),
        ),
        status: SessionStatus.processing,
        createdAt: DateTime(2026, 10, 5),
      );

      expect(s.combinedQuality, isNull);
    });
  });

  group('observabilidade (§32)', () {
    test('o tempo é medido, não estimado', () async {
      final MultiViewAnalysisService servico = MultiViewAnalysisService(
        classifier: ScriptedClassificationService(<Map<String, double>>[
          <String, double>{'a': 0.90, 'b': 0.10},
        ]),
      );

      final MultiViewAnalysis a = await servico.analyse(sessao());

      expect(a.elapsed, greaterThanOrEqualTo(Duration.zero));
      expect(a.toMap()['elapsedMs'], isA<int>());
    });

    test('o mapa de auditoria carrega as etapas, não só o veredito', () async {
      final MultiViewAnalysisService servico = MultiViewAnalysisService(
        classifier: ScriptedClassificationService(<Map<String, double>>[
          <String, double>{'a': 0.85, 'b': 0.15},
          <String, double>{'a': 0.80, 'b': 0.20},
        ]),
      );

      final Map<String, Object?> m =
          (await servico.analyse(sessao(segunda: vista(ImageCaptureInstruction.tail))))
              .toMap();

      expect(m.keys, containsAll(<String>['views', 'fused', 'confidence']));
      final Map<String, Object?> fundido = m['fused']! as Map<String, Object?>;
      expect(fundido['rawTopScore'], isA<double>(),
          reason: 'o valor cru precisa estar no registro: é ele que explica '
              'uma rejeição depois');
      expect(fundido['consistency'], isA<Map<String, Object?>>());
    });
  });
}

// -- Apoio --------------------------------------------------------------------

ImageQualityResult _qualidade(ImageQuality medida) => ImageQualityResult(
      quality: medida,
      score: switch (medida) {
        ImageQuality.good => 0.9,
        ImageQuality.acceptable => 0.7,
        ImageQuality.poor => 0.4,
        ImageQuality.invalid => 0.0,
      },
      brightness: 0.5,
      contrast: 0.2,
      sharpness: 0.006,
      width: 1600,
      height: 1200,
      warnings: const <ImageQualityWarning>[],
    );

/// Cena sintética com textura suficiente para passar na medida de nitidez.
Uint8List _foto() {
  final img.Image imagem = img.Image(width: 1200, height: 900);
  for (int y = 0; y < imagem.height; y++) {
    for (int x = 0; x < imagem.width; x++) {
      final int xadrez = ((x ~/ 7) + (y ~/ 7)) % 2 == 0 ? 55 : 190;
      final int ruido = ((x * 31 + y * 17) % 23) - 11;
      final int v = (xadrez + ruido).clamp(0, 255);
      imagem.setPixelRgb(x, y, v, v, (v * 0.9).round().clamp(0, 255));
    }
  }
  return Uint8List.fromList(
    img.encodeJpg(imagem, quality: ImageLimits.originalQuality),
  );
}

/// Classificador de teste que devolve scores escritos à mão.
///
/// Vive aqui, e não em `test/`, porque o modo de demonstração também precisa
/// dele: sem Firebase e sem modelo, é o que permite percorrer o fluxo inteiro
/// numa apresentação.
///
/// # O selo que ele carrega
/// `isMock: true` e `modelVersion` com prefixo `mock-`. Nada que sai daqui
/// pode ser confundido com saída de modelo, nem no banco nem na tela — a
/// mesma trava que a Fase 4 estabeleceu, e que o §12 do briefing exige.
class ScriptedClassificationService implements SpeciesClassificationService {
  ScriptedClassificationService(this.scoresPorChamada);

  /// Um mapa espécie → score por chamada, na ordem em que forem pedidos.
  /// Esgotada a lista, devolve o último — para que um teste com uma vista só
  /// não precise repetir a entrada.
  final List<Map<String, double>> scoresPorChamada;

  /// Contador de instância, não estático.
  ///
  /// A primeira versão deste dublê guardava a posição num `static`, e isso é
  /// uma armadilha: os arquivos de teste rodam em paralelo, e dois testes
  /// usando o dublê ao mesmo tempo consumiriam o mesmo contador. A falha
  /// resultante seria intermitente e apareceria como "a fusão às vezes usa os
  /// scores errados" — o pior tipo de defeito para investigar.
  int _chamada = 0;

  @override
  Future<ClassificationResult> classify(ProcessedImage image) async {
    if (scoresPorChamada.isEmpty) {
      return const ClassificationResult.notEvaluated();
    }
    final Map<String, double> scores = scoresPorChamada[
        _chamada < scoresPorChamada.length
            ? _chamada++
            : scoresPorChamada.length - 1];

    final List<MapEntry<String, double>> ordenado = scores.entries.toList()
      ..sort((MapEntry<String, double> a, MapEntry<String, double> b) =>
          b.value.compareTo(a.value));

    return ClassificationResult(
      modelVersion: ClassificationResult.mockVersion,
      isMock: true,
      candidates: ordenado
          .map((MapEntry<String, double> e) => SpeciesCandidate(
                speciesId: e.key,
                scientificName: e.key,
                confidence: e.value,
              ))
          .toList(growable: false),
    );
  }
}
