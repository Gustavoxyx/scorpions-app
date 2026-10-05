import 'package:flutter_test/flutter_test.dart';
import 'package:scorpions/data/models/capture_instruction.dart';
import 'package:scorpions/data/models/classification.dart';
import 'package:scorpions/data/models/view_prediction.dart';
import 'package:scorpions/data/services/multi_view_fusion_service.dart';

/// Testes da fusão multi-view e da consistência cruzada.
///
/// Eles rodam sem modelo nenhum, com vetores de score escritos à mão. Isso é
/// deliberado: fusão e consistência são **aritmética**, e a correção delas não
/// depende de qual classificador produziu os números. Quando o modelo chegar,
/// estes testes continuam valendo sem uma linha de mudança — e qualquer
/// regressão aqui aparece sem precisar de dataset, GPU ou rede.
void main() {
  const LateFusionService fusao = LateFusionService();

  ViewPrediction vista(
    CaptureType tipo,
    Map<String, double> scores, {
    double peso = 1.0,
  }) {
    final List<MapEntry<String, double>> ordenado = scores.entries.toList()
      ..sort((MapEntry<String, double> a, MapEntry<String, double> b) =>
          b.value.compareTo(a.value));
    return ViewPrediction(
      captureType: tipo,
      modelVersion: 'teste-v1',
      qualityWeight: peso,
      candidates: ordenado
          .map((MapEntry<String, double> e) => SpeciesCandidate(
                speciesId: e.key,
                scientificName: e.key,
                confidence: e.value,
              ))
          .toList(growable: false),
    );
  }

  group('consistência entre vistas', () {
    test('distribuições idênticas concordam totalmente', () {
      final ViewPrediction a =
          vista(CaptureType.topView, <String, double>{'x': 0.7, 'y': 0.3});
      final ViewPrediction b =
          vista(CaptureType.tail, <String, double>{'x': 0.7, 'y': 0.3});

      final CrossViewConsistency c = CrossViewConsistency.between(a, b);

      expect(c.agreeOnTop1, isTrue);
      expect(c.topKOverlap, 1.0);
      expect(c.distributionAgreement, closeTo(1.0, 1e-9));
      expect(c.isConflicting, isFalse);
    });

    test('distribuições sem espécie em comum não concordam em nada', () {
      final ViewPrediction a =
          vista(CaptureType.topView, <String, double>{'x': 1.0});
      final ViewPrediction b =
          vista(CaptureType.tail, <String, double>{'y': 1.0});

      final CrossViewConsistency c = CrossViewConsistency.between(a, b);

      expect(c.agreeOnTop1, isFalse);
      expect(c.topKOverlap, 0.0);
      // Jensen-Shannon em base 2 vale exatamente 1 para distribuições
      // disjuntas — é o limite superior da medida.
      expect(c.distributionAgreement, closeTo(0.0, 1e-9));
      expect(c.isConflicting, isTrue);
    });

    test('mesmo vencedor com convicções diferentes não é acordo total', () {
      final ViewPrediction firme =
          vista(CaptureType.topView, <String, double>{'x': 0.95, 'y': 0.05});
      final ViewPrediction hesitante =
          vista(CaptureType.tail, <String, double>{'x': 0.40, 'y': 0.35, 'z': 0.25});

      final CrossViewConsistency c =
          CrossViewConsistency.between(firme, hesitante);

      expect(c.agreeOnTop1, isTrue,
          reason: 'as duas elegem x');
      expect(c.distributionAgreement, lessThan(0.9),
          reason: 'concordar no topo não é concordar na distribuição — é '
              'exatamente o caso que uma medida binária esconderia');
    });

    test('a medida é simétrica: ordem das vistas não altera o resultado', () {
      final ViewPrediction a =
          vista(CaptureType.topView, <String, double>{'x': 0.6, 'y': 0.3, 'z': 0.1});
      final ViewPrediction b =
          vista(CaptureType.tail, <String, double>{'y': 0.5, 'x': 0.4, 'w': 0.1});

      expect(
        CrossViewConsistency.between(a, b).distributionAgreement,
        closeTo(CrossViewConsistency.between(b, a).distributionAgreement, 1e-12),
        reason: 'foi por isso que Jensen-Shannon foi escolhida no lugar de '
            'Kullback-Leibler, que é assimétrica',
      );
    });

    test('vista única é tratada como acordo, não como conflito', () {
      final FusedPrediction f = fusao.fuse(<ViewPrediction>[
        vista(CaptureType.topView, <String, double>{'x': 0.8, 'y': 0.2}),
      ]);

      expect(f.consistency.agreeOnTop1, isTrue);
      expect(f.consistency.isConflicting, isFalse,
          reason: 'quem só conseguiu uma foto não pode ser punido por isso');
      expect(f.viewCount, 1);
    });
  });

  group('fusão', () {
    test('vistas concordantes reforçam o mesmo vencedor', () {
      final FusedPrediction f = fusao.fuse(<ViewPrediction>[
        vista(CaptureType.topView, <String, double>{'x': 0.80, 'y': 0.20}),
        vista(CaptureType.tail, <String, double>{'x': 0.90, 'y': 0.10}),
      ]);

      expect(f.top!.speciesId, 'x');
      expect(f.margin, greaterThan(0.5));
      expect(f.viewCount, 2);
    });

    test('vistas em conflito produzem fusão sem vencedor claro', () {
      final FusedPrediction f = fusao.fuse(<ViewPrediction>[
        vista(CaptureType.topView, <String, double>{'x': 0.90, 'y': 0.10}),
        vista(CaptureType.tail, <String, double>{'y': 0.90, 'x': 0.10}),
      ]);

      expect(f.margin, lessThan(0.1),
          reason: 'o desacordo precisa aparecer como hesitação, não ser '
              'escondido pela média');
      expect(f.consistency.isConflicting, isFalse,
          reason: 'elas discordam de quem vence, mas olham para as mesmas '
              'duas hipóteses — desacordo brando, não conflito');
    });

    test('espécie ausente de uma vista conta como zero, não some do divisor', () {
      // `z` aparece só na segunda vista. Se a média fosse calculada sobre o
      // número de vistas que a citaram, `z` sairia com 0,30 e passaria na
      // frente de `x`, que tem apoio das duas.
      final FusedPrediction f = fusao.fuse(
        <ViewPrediction>[
          vista(CaptureType.topView, <String, double>{'x': 0.60, 'y': 0.40}),
          vista(CaptureType.tail, <String, double>{'x': 0.40, 'z': 0.30, 'y': 0.30}),
        ],
        strategy: FusionStrategy.average,
      );

      expect(f.top!.speciesId, 'x');
      final double zScore = f.candidates
          .firstWhere((SpeciesCandidate c) => c.speciesId == 'z')
          .confidence;
      final double xScore = f.top!.confidence;
      expect(zScore, lessThan(xScore));
    });

    test('ponderação por confiança dá mais voz à vista decidida', () {
      final ViewPrediction decidida =
          vista(CaptureType.topView, <String, double>{'x': 0.95, 'y': 0.05});
      final ViewPrediction hesitante =
          vista(CaptureType.tail, <String, double>{'y': 0.52, 'x': 0.48});

      final FusedPrediction media = fusao.fuse(
        <ViewPrediction>[decidida, hesitante],
        strategy: FusionStrategy.average,
      );
      final FusedPrediction ponderada = fusao.fuse(
        <ViewPrediction>[decidida, hesitante],
        strategy: FusionStrategy.confidenceWeighted,
      );

      expect(media.top!.speciesId, 'x');
      expect(ponderada.top!.speciesId, 'x');
      expect(
        ponderada.top!.confidence,
        greaterThan(media.top!.confidence),
        reason: 'a vista que hesitou entre duas espécies deve pesar menos que '
            'a que foi direta',
      );
    });

    test('ponderação por qualidade reduz a voz da foto ruim', () {
      final ViewPrediction boa = vista(
        CaptureType.topView,
        <String, double>{'x': 0.80, 'y': 0.20},
        peso: 1.0,
      );
      final ViewPrediction ruim = vista(
        CaptureType.tail,
        <String, double>{'y': 0.80, 'x': 0.20},
        peso: 0.35,
      );

      final FusedPrediction f = fusao.fuse(
        <ViewPrediction>[boa, ruim],
        strategy: FusionStrategy.qualityWeighted,
      );

      expect(f.top!.speciesId, 'x',
          reason: 'o modelo não sabe que a segunda foto está ruim; quem sabe '
              'é o pipeline, e é por isso que o peso vem de fora');
    });

    test('estratégia máximo não pune desacordo — e por isso não decide sozinha',
        () {
      final FusedPrediction f = fusao.fuse(
        <ViewPrediction>[
          vista(CaptureType.topView, <String, double>{'x': 0.90, 'y': 0.10}),
          vista(CaptureType.tail, <String, double>{'y': 0.90, 'x': 0.10}),
        ],
        strategy: FusionStrategy.maximum,
      );

      // As duas saem com 0,90 e a renormalização as deixa empatadas em 0,50.
      expect(f.margin, closeTo(0.0, 1e-9),
          reason: 'documenta a limitação declarada no enum: `maximum` preserva '
              'a evidência de cada vista e não resolve o conflito');
    });

    test('a saída sempre soma 1', () {
      for (final FusionStrategy e in FusionStrategy.values) {
        final FusedPrediction f = fusao.fuse(
          <ViewPrediction>[
            vista(CaptureType.topView, <String, double>{'x': 0.5, 'y': 0.3}),
            vista(CaptureType.tail, <String, double>{'x': 0.4, 'z': 0.2}),
          ],
          strategy: e,
        );
        final double soma = f.candidates
            .fold(0.0, (double a, SpeciesCandidate c) => a + c.confidence);
        expect(soma, closeTo(1.0, 1e-9), reason: 'estratégia ${e.id}');
      }
    });

    test('sem predição nenhuma, devolve não avaliado — nunca um palpite', () {
      final FusedPrediction f = fusao.fuse(const <ViewPrediction>[
        ViewPrediction(
          captureType: CaptureType.topView,
          candidates: <SpeciesCandidate>[],
          modelVersion: 'teste-v1',
        ),
      ]);

      expect(f.wasEvaluated, isFalse);
      expect(f.top, isNull);
      expect(f.viewCount, 0);
    });

    test('Top-3 nunca devolve mais que três', () {
      final FusedPrediction f = fusao.fuse(<ViewPrediction>[
        vista(CaptureType.topView, <String, double>{
          'a': 0.4, 'b': 0.25, 'c': 0.2, 'd': 0.1, 'e': 0.05,
        }),
      ]);

      expect(f.topThree.length, 3);
      expect(f.topThree.first.speciesId, 'a');
    });

    test('a ordem das vistas não altera o resultado', () {
      final ViewPrediction a =
          vista(CaptureType.topView, <String, double>{'x': 0.7, 'y': 0.3});
      final ViewPrediction b =
          vista(CaptureType.tail, <String, double>{'y': 0.6, 'x': 0.4});

      for (final FusionStrategy e in FusionStrategy.values) {
        final FusedPrediction ab =
            fusao.fuse(<ViewPrediction>[a, b], strategy: e);
        final FusedPrediction ba =
            fusao.fuse(<ViewPrediction>[b, a], strategy: e);
        expect(ab.top!.confidence, closeTo(ba.top!.confidence, 1e-9),
            reason: 'estratégia ${e.id}: fusão precisa ser comutativa, senão '
                'a ordem de captura viraria variável escondida');
      }
    });
  });
}
