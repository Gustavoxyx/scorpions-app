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

/// O contrato da análise: uma **sessão inteira** entra, uma conclusão sai.
///
/// # Por que a sessão, e não a imagem
/// O pipeline chamava um classificador por imagem. Esse nível só comporta
/// fusão tardia — classificar cada foto sozinha e combinar depois. Um modelo
/// que recebe as duas fotos juntas não cabe num contrato que entrega uma de
/// cada vez.
///
/// Neste nível cabem as quatro combinações que a fase da IA ainda vai decidir:
/// fusão tardia ou modelo conjunto, no aparelho ou no servidor. É também o
/// nível do `POST /v1/analyses`, que recebe a sessão e suas vistas.
abstract interface class IdentificationAnalyzer {
  Future<MultiViewAnalysis> analyse(IdentificationSession session);
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
class MultiViewAnalysisService implements IdentificationAnalyzer {
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

  @override
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
