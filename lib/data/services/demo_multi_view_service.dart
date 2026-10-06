import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/capture_instruction.dart';
import '../models/classification.dart';
import '../models/identification.dart';
import '../models/image_quality.dart';
import '../models/secondary_view.dart';
import '../models/species.dart';
import '../models/view_prediction.dart';
import 'confidence_engine.dart';
import 'multi_view_fusion_service.dart';

/// O que a fusão simulada produziu.
@immutable
class DemoFusionOutcome {
  const DemoFusionOutcome({
    required this.predictions,
    required this.assessment,
    required this.summary,
  });

  /// Hipóteses já fundidas, da mais para a menos provável.
  final List<SpeciesPrediction> predictions;

  final ConfidenceAssessment assessment;
  final MultiViewSummary summary;

  /// Se a decisão permite mostrar uma espécie.
  ///
  /// `reject` e `humanReview` não permitem: no primeiro o modelo não sabe, no
  /// segundo as duas fotos discordam — e escolher uma delas em silêncio seria
  /// exatamente o que a segunda foto existe para impedir.
  bool get showsSpecies =>
      assessment.level != DecisionLevel.reject &&
      assessment.level != DecisionLevel.humanReview;
}

/// Funde duas vistas no **modo de demonstração**.
///
/// # O que aqui é simulado, e o que não é
/// Simulado: o que cada foto "disse". Não existe modelo, então a opinião da
/// primeira vista vem do motor simulado de sempre, e a da segunda é derivada
/// dela — ver [combine].
///
/// **Não** simulado: tudo o que acontece depois. A fusão é o
/// [LateFusionService] de produção, a decisão é o [ConfidenceEngine] de
/// produção, e a concordância entre vistas é a Jensen-Shannon de produção — a
/// mesma aritmética que o teste de paridade confere contra o backend.
///
/// É o que torna a demonstração útil para o TCC: dá para mostrar, com o
/// aplicativo na mão, o que o sistema faz quando duas fotos concordam e quando
/// discordam. O que não dá para mostrar — e a tela diz isso, com o selo de dado
/// simulado — é o sistema acertando a espécie.
///
/// # Por que isto nunca roda com Firebase
/// O controlador só chama este serviço quando `demonstration` é verdadeiro, e
/// ele só é verdadeiro no modo `mock`. Com banco de verdade, inventar o que uma
/// foto disse gravaria ficção no histórico de alguém.
class DemoMultiViewService {
  DemoMultiViewService({
    Random? random,
    this.fusion = const LateFusionService(),
    this.engine = const ConfidenceEngine(),
    this.disagreementRate = 0.2,
    this.strategy = FusionStrategy.confidenceWeighted,
  }) : _random = random ?? Random();

  final Random _random;
  final MultiViewFusionService fusion;
  final ConfidenceEngine engine;

  /// A estratégia de fusão. O padrão é o mesmo de `MultiViewAnalysisService`,
  /// para que a demonstração mostre o que a produção faria.
  ///
  /// Vale saber o que cada uma faz com a **qualidade** da foto, porque não é
  /// óbvio: na ponderada por confiança (a padrão), quem pesa é a firmeza de
  /// cada vista, e a qualidade medida **não entra na fusão** — entra só na
  /// decisão, pelo motor de confiança. A qualidade só altera os scores
  /// fundidos em [FusionStrategy.qualityWeighted].
  ///
  /// Um teste deste projeto assumiu o contrário e falhou. Qual das duas
  /// estratégias serve melhor é pergunta que só um modelo avaliado responde;
  /// por ora as quatro existem para serem comparadas.
  final FusionStrategy strategy;

  /// Com que frequência a segunda vista simulada **discorda** da primeira.
  ///
  /// Um em cada cinco, e a escolha é de produto: o caminho de "as fotos
  /// divergem" precisa aparecer numa demonstração de dez minutos sem que seja
  /// preciso repetir vinte vezes. É o mesmo raciocínio do motor simulado, que
  /// rejeita 18% das análises de propósito — o fluxo de "não sei" deve ser
  /// exercitado, não escondido.
  ///
  /// **Não é uma taxa medida de nada.** Nenhum modelo foi avaliado, e este
  /// número não descreve o comportamento de classificador nenhum.
  final double disagreementRate;

  /// Funde a primeira vista com uma segunda simulada.
  ///
  /// [first] são as hipóteses da primeira vista, como o motor simulado as
  /// produziu. A segunda é derivada delas: na maior parte das vezes concorda,
  /// com os scores levemente diferentes; em [disagreementRate] das vezes troca
  /// a primeira hipótese pela segunda.
  ///
  /// Derivada, e não sorteada do zero, porque duas opiniões sorteadas de forma
  /// independente sobre oito espécies discordariam quase sempre — e uma
  /// demonstração em que as fotos nunca concordam ensinaria o contrário do que
  /// a fusão faz.
  DemoFusionOutcome combine({
    required List<SpeciesPrediction> first,
    required CaptureType secondType,
    ImageQuality? firstQuality,
    ImageQuality? secondQuality,
  }) {
    assert(first.isNotEmpty, 'não há o que fundir sem a primeira vista');

    final List<SpeciesPrediction> second = _segundaVista(first);

    final FusedPrediction fundido = fusion.fuse(
      <ViewPrediction>[
        _comoVista(first, CaptureType.topView, firstQuality),
        _comoVista(second, secondType, secondQuality),
      ],
      strategy: strategy,
    );

    final ConfidenceAssessment decisao = engine.assess(
      fundido,
      combinedQuality: _melhor(firstQuality, secondQuality),
    );

    // As espécies completas vêm da primeira vista: a fusão trabalha com
    // identificadores, e a tela precisa do objeto inteiro.
    final Map<String, Species> porId = <String, Species>{
      for (final SpeciesPrediction p in first) p.species.id: p.species,
    };

    return DemoFusionOutcome(
      predictions: <SpeciesPrediction>[
        for (final SpeciesCandidate c in fundido.candidates)
          if (porId[c.speciesId] != null)
            SpeciesPrediction(species: porId[c.speciesId]!, score: c.confidence),
      ],
      assessment: decisao,
      summary: MultiViewSummary(
        viewCount: fundido.viewCount,
        agreeOnTop1: fundido.consistency.agreeOnTop1,
        agreement: fundido.consistency.distributionAgreement,
        decisionLevel: decisao.level.id,
        reasons: decisao.reasons
            .map((DecisionReason r) => r.id)
            .toList(growable: false),
        thresholdsCalibrated: decisao.thresholdsCalibrated,
      ),
    );
  }

  // -- Interno ----------------------------------------------------------------

  /// A opinião simulada da segunda fotografia.
  List<SpeciesPrediction> _segundaVista(List<SpeciesPrediction> first) {
    final bool discorda =
        first.length >= 2 && _random.nextDouble() < disagreementRate;

    // Mesmas espécies, scores com uma variação pequena: duas fotos do mesmo
    // animal não produziriam números idênticos nem com um modelo de verdade.
    final List<SpeciesPrediction> variada = <SpeciesPrediction>[
      for (final SpeciesPrediction p in first)
        SpeciesPrediction(
          species: p.species,
          score: (p.score * (0.9 + _random.nextDouble() * 0.2)).clamp(0.0, 1.0),
        ),
    ];

    if (!discorda) return variada;

    // Discordância: a segunda vista dá à segunda hipótese o score que a
    // primeira hipótese tinha, e vice-versa. As duas fotos passam a apontar
    // espécies diferentes com a mesma firmeza — o caso que a consistência
    // cruzada existe para pegar.
    return <SpeciesPrediction>[
      SpeciesPrediction(species: variada[1].species, score: variada[0].score),
      SpeciesPrediction(species: variada[0].species, score: variada[1].score),
      ...variada.skip(2),
    ];
  }

  ViewPrediction _comoVista(
    List<SpeciesPrediction> hipoteses,
    CaptureType tipo,
    ImageQuality? qualidade,
  ) {
    final List<SpeciesPrediction> ordenadas =
        List<SpeciesPrediction>.of(hipoteses)
          ..sort((SpeciesPrediction a, SpeciesPrediction b) =>
              b.score.compareTo(a.score));

    return ViewPrediction(
      captureType: tipo,
      // O selo de dado simulado viaja junto: nada que sai daqui pode ser
      // confundido com saída de modelo.
      modelVersion: ClassificationResult.mockVersion,
      // O peso de qualidade vem do que o aparelho mediu da foto, não do
      // "modelo" — como no caminho de produção. Se ele é USADO depende da
      // estratégia: ver [strategy].
      qualityWeight: ConfidenceEngine.weightFor(qualidade),
      candidates: ordenadas
          .map((SpeciesPrediction p) => SpeciesCandidate(
                speciesId: p.species.id,
                scientificName: p.species.scientificName,
                confidence: p.score,
              ))
          .toList(growable: false),
    );
  }

  /// A melhor das duas medidas, não a média — a mesma escolha de
  /// `IdentificationSession.combinedQuality`, pelo mesmo motivo: a pergunta é
  /// "existe informação suficiente?", e uma vista boa responde sim.
  static ImageQuality? _melhor(ImageQuality? a, ImageQuality? b) {
    if (a == null) return b;
    if (b == null) return a;
    // `ImageQuality` é declarado do melhor para o pior.
    return a.index <= b.index ? a : b;
  }
}
