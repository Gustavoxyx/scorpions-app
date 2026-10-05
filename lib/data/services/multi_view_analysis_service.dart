import 'package:flutter/foundation.dart';

import '../models/classification.dart';
import '../models/detection.dart';
import '../models/identification_session.dart';
import '../models/processed_image.dart';
import '../models/view_prediction.dart';
import 'confidence_engine.dart';
import 'multi_view_fusion_service.dart';
import 'scorpion_detection_service.dart';
import 'species_classification_service.dart';

/// O que a análise produziu, da detecção à decisão.
///
/// Guarda as etapas intermediárias, e não só o veredito. O §39 exige poder
/// reconstruir uma identificação — e reconstruir significa responder "o que
/// cada foto disse?", não apenas "qual foi o resultado".
@immutable
class MultiViewAnalysis {
  const MultiViewAnalysis({
    required this.detections,
    required this.viewPredictions,
    required this.fused,
    required this.assessment,
    required this.elapsed,
  });

  /// Nenhum modelo avaliou — estado honesto enquanto o classificador não
  /// existe. Não é o mesmo que "nenhuma espécie corresponde".
  const MultiViewAnalysis.notEvaluated()
      : detections = const <ScorpionDetectionResult>[],
        viewPredictions = const <ViewPrediction>[],
        fused = const FusedPrediction.notEvaluated(),
        assessment = const ConfidenceAssessment.notEvaluated(),
        elapsed = Duration.zero;

  final List<ScorpionDetectionResult> detections;
  final List<ViewPrediction> viewPredictions;
  final FusedPrediction fused;
  final ConfidenceAssessment assessment;

  /// Tempo de inferência e fusão (§32). Medido, não estimado.
  final Duration elapsed;

  bool get wasEvaluated => fused.wasEvaluated;

  /// Se alguma vista afirmou que há um escorpião.
  ///
  /// `null` quando nenhuma avaliou — o que é diferente de `false`, que
  /// significaria "olhamos e não é um escorpião".
  bool? get hasScorpion {
    final List<bool> respostas = detections
        .where((ScorpionDetectionResult d) => d.wasEvaluated)
        .map((ScorpionDetectionResult d) => d.isScorpion!)
        .toList(growable: false);
    if (respostas.isEmpty) return null;
    return respostas.any((bool r) => r);
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'elapsedMs': elapsed.inMilliseconds,
        'hasScorpion': hasScorpion,
        'views':
            viewPredictions.map((ViewPrediction p) => p.toMap()).toList(growable: false),
        'fused': fused.toMap(),
        'confidence': assessment.toMap(),
      };
}

/// Roda a análise sobre as vistas de uma sessão (§6, §7, §8, §9, §12).
///
/// # Por que as vistas rodam em paralelo
/// Porque não dependem uma da outra. O §6 pede explicitamente que não se
/// espere a primeira terminar para começar a segunda quando não houver
/// dependência real — e aqui não há: detectar e classificar a foto de cima
/// não precisa de nada que venha do close da cauda.
///
/// Na web `compute` executa na mesma thread, então o paralelismo é de
/// entrada e saída, não de CPU. Ainda assim vale: a maior parte do tempo de
/// uma inferência remota é espera de rede.
///
/// # O que acontece quando não há modelo
/// Tudo isto roda, e o resultado é `notEvaluated`. Os serviços simulados
/// devolvem listas vazias em vez de espécies sorteadas, a fusão não tem o que
/// fundir, e a decisão diz que nada foi avaliado. Nenhuma espécie falsa
/// atravessa este caminho — é a mesma garantia da Fase 4, agora com duas
/// imagens.
class MultiViewAnalysisService {
  const MultiViewAnalysisService({
    this.detector = const MockScorpionDetectionService(),
    this.classifier = const MockSpeciesClassificationService(),
    this.fusion = const LateFusionService(),
    this.confidence = const ConfidenceEngine(),
    this.strategy = FusionStrategy.confidenceWeighted,
  });

  final ScorpionDetectionService detector;
  final SpeciesClassificationService classifier;
  final MultiViewFusionService fusion;
  final ConfidenceEngine confidence;
  final FusionStrategy strategy;

  Future<MultiViewAnalysis> analyse(IdentificationSession session) async {
    final List<SessionView> vistas = session.analysableViews;
    if (vistas.isEmpty) return const MultiViewAnalysis.notEvaluated();

    final Stopwatch relogio = Stopwatch()..start();

    // As vistas inteiras em paralelo — cada uma detecta e classifica a sua.
    final List<_ViewOutcome> saidas = await Future.wait<_ViewOutcome>(
      vistas.map(_analysarVista),
    );

    relogio.stop();

    final List<ViewPrediction> predicoes = saidas
        .map((_ViewOutcome o) => o.prediction)
        .where((ViewPrediction p) => !p.isEmpty)
        .toList(growable: false);

    final FusedPrediction fundido =
        fusion.fuse(predicoes, strategy: strategy);

    return MultiViewAnalysis(
      detections:
          saidas.map((_ViewOutcome o) => o.detection).toList(growable: false),
      viewPredictions:
          saidas.map((_ViewOutcome o) => o.prediction).toList(growable: false),
      fused: fundido,
      assessment: confidence.assess(
        fundido,
        combinedQuality: session.combinedQuality,
      ),
      elapsed: relogio.elapsed,
    );
  }

  Future<_ViewOutcome> _analysarVista(SessionView vista) async {
    final ProcessedImage imagem = vista.processed!;

    // Detectar e classificar também não dependem um do outro hoje. Quando a
    // detecção passar a recortar a região antes de classificar, isto vira
    // sequencial — e o comentário some junto com o paralelismo.
    final List<Object> resultados = await Future.wait<Object>(<Future<Object>>[
      detector.detect(imagem),
      classifier.classify(imagem),
    ]);

    final ScorpionDetectionResult deteccao =
        resultados[0] as ScorpionDetectionResult;
    final ClassificationResult classificacao =
        resultados[1] as ClassificationResult;

    return _ViewOutcome(
      detection: deteccao,
      prediction: ViewPrediction(
        captureType: vista.instruction.captureType,
        candidates: classificacao.candidates,
        modelVersion: classificacao.modelVersion,
        // O peso vem da medida do pipeline, não do modelo. O classificador
        // não sabe que está olhando para uma foto borrada; ele responde com a
        // mesma firmeza de sempre, e é justamente aí que erra com confiança.
        qualityWeight: ConfidenceEngine.weightFor(vista.quality?.quality),
      ),
    );
  }
}

@immutable
class _ViewOutcome {
  const _ViewOutcome({required this.detection, required this.prediction});

  final ScorpionDetectionResult detection;
  final ViewPrediction prediction;
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
@visibleForTesting
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
