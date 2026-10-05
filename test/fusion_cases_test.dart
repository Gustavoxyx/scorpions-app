import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scorpions/data/models/capture_instruction.dart';
import 'package:scorpions/data/models/classification.dart';
import 'package:scorpions/data/models/image_quality.dart';
import 'package:scorpions/data/models/view_prediction.dart';
import 'package:scorpions/data/services/confidence_engine.dart';
import 'package:scorpions/data/services/multi_view_fusion_service.dart';

/// GERA os casos canônicos de fusão e decisão, a partir da implementação Dart.
///
/// # Por que isto existe
/// A mesma lógica vive em dois lugares: aqui, em Dart, e em
/// `backend/app/fusion.py`. Duplicação é dívida, e esta é assumida de olhos
/// abertos — o servidor precisa dela porque é ele quem grava o resultado
/// (auditoria HIGH-1), e o aplicativo precisa dela para o modo de
/// demonstração, que roda sem rede e sem backend.
///
/// O risco de duas implementações é divergirem em silêncio. Então nenhuma
/// delas é a referência por decreto: este arquivo **executa** a versão Dart e
/// escreve o que ela produziu em `backend/tests/fusion_cases.json`, e o teste
/// Python roda os mesmos casos contra a versão dele.
///
/// Os números não são escritos à mão em lugar nenhum. Enquanto o teste
/// inventa o dado, ele testa a si mesmo — foi assim que o bug do campo `role`
/// passou despercebido na Fase 3, e `contract_shapes_test.dart` nasceu da
/// mesma lição.
///
/// # Como rodar
///     flutter test test/fusion_cases_test.dart
///     cd backend && python -m pytest tests/test_parity.py
void main() {
  const LateFusionService fusao = LateFusionService();
  const ConfidenceEngine motor = ConfidenceEngine();

  ViewPrediction vista(
    String tipo,
    Map<String, double> scores, {
    double peso = 1.0,
  }) {
    final List<MapEntry<String, double>> ordenado = scores.entries.toList()
      ..sort((MapEntry<String, double> a, MapEntry<String, double> b) =>
          b.value.compareTo(a.value));
    return ViewPrediction(
      captureType: CaptureType.fromId(tipo),
      modelVersion: 'parity-v1',
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

  test('gera os casos canônicos de fusão para a verificação de paridade', () {
    // Cada entrada é uma situação que o sistema vai encontrar. As de desacordo
    // e empate estão aqui de propósito: são onde duas implementações da mesma
    // ideia têm mais chance de divergir.
    final List<Map<String, Object?>> entradas = <Map<String, Object?>>[
      <String, Object?>{
        'name': 'vistas concordantes, convicção alta',
        'views': <Map<String, Object?>>[
          <String, Object?>{'type': 'top_view', 'scores': <String, double>{'a': 0.90, 'b': 0.07, 'c': 0.03}},
          <String, Object?>{'type': 'tail', 'scores': <String, double>{'a': 0.88, 'b': 0.09, 'c': 0.03}},
        ],
        'quality': 'good',
      },
      <String, Object?>{
        'name': 'vistas em lados opostos do catalogo',
        'views': <Map<String, Object?>>[
          <String, Object?>{'type': 'top_view', 'scores': <String, double>{'a': 0.95, 'b': 0.05}},
          <String, Object?>{'type': 'tail', 'scores': <String, double>{'d': 0.95, 'e': 0.05}},
        ],
        'quality': 'good',
      },
      <String, Object?>{
        'name': 'probabilidade espalhada — precisa rejeitar',
        'views': <Map<String, Object?>>[
          <String, Object?>{'type': 'top_view', 'scores': <String, double>{'a': 0.30, 'b': 0.28}},
          <String, Object?>{'type': 'tail', 'scores': <String, double>{'b': 0.31, 'a': 0.29}},
        ],
        'quality': 'good',
      },
      <String, Object?>{
        'name': 'empate tecnico no topo',
        'views': <Map<String, Object?>>[
          <String, Object?>{'type': 'top_view', 'scores': <String, double>{'a': 0.51, 'b': 0.49}},
        ],
        'quality': 'good',
      },
      <String, Object?>{
        'name': 'scores identicos — exercita o desempate',
        'views': <Map<String, Object?>>[
          <String, Object?>{'type': 'top_view', 'scores': <String, double>{'z': 0.40, 'a': 0.40, 'm': 0.20}},
        ],
        'quality': 'good',
      },
      <String, Object?>{
        'name': 'uma vista so, convicta',
        'views': <Map<String, Object?>>[
          <String, Object?>{'type': 'top_view', 'scores': <String, double>{'a': 0.92, 'b': 0.05, 'c': 0.03}},
        ],
        'quality': 'good',
      },
      <String, Object?>{
        'name': 'segunda vista com qualidade ruim',
        'views': <Map<String, Object?>>[
          <String, Object?>{'type': 'top_view', 'scores': <String, double>{'a': 0.80, 'b': 0.20}, 'weight': 1.0},
          <String, Object?>{'type': 'tail', 'scores': <String, double>{'b': 0.80, 'a': 0.20}, 'weight': 0.35},
        ],
        'quality': 'poor',
      },
      <String, Object?>{
        'name': 'especies parcialmente sobrepostas',
        'views': <Map<String, Object?>>[
          <String, Object?>{'type': 'top_view', 'scores': <String, double>{'a': 0.60, 'b': 0.40}},
          <String, Object?>{'type': 'tail', 'scores': <String, double>{'a': 0.40, 'c': 0.35, 'b': 0.25}},
        ],
        'quality': 'acceptable',
      },
      <String, Object?>{
        'name': 'nenhuma predicao',
        'views': <Map<String, Object?>>[],
        'quality': null,
      },
    ];

    final List<Map<String, Object?>> casos = <Map<String, Object?>>[];

    for (final Map<String, Object?> entrada in entradas) {
      final List<ViewPrediction> vistas = <ViewPrediction>[
        for (final Map<String, Object?> v
            in (entrada['views']! as List<Map<String, Object?>>))
          vista(
            v['type']! as String,
            (v['scores']! as Map<String, double>),
            peso: (v['weight'] as double?) ?? 1.0,
          ),
      ];

      final ImageQuality? medida = switch (entrada['quality'] as String?) {
        'good' => ImageQuality.good,
        'acceptable' => ImageQuality.acceptable,
        'poor' => ImageQuality.poor,
        'invalid' => ImageQuality.invalid,
        _ => null,
      };

      // Cada caso é avaliado nas quatro estratégias: é onde as diferenças
      // entre implementações aparecem.
      for (final FusionStrategy estrategia in FusionStrategy.values) {
        final FusedPrediction f = fusao.fuse(vistas, strategy: estrategia);
        final ConfidenceAssessment a =
            motor.assess(f, combinedQuality: medida);

        casos.add(<String, Object?>{
          'name': '${entrada['name']} [${estrategia.id}]',
          'input': <String, Object?>{
            'strategy': estrategia.id,
            'quality': entrada['quality'],
            'views': entrada['views'],
          },
          'expected': <String, Object?>{
            'fused': f.toMap(),
            'confidence': a.toMap(),
          },
        });
      }
    }

    final File destino = File('backend/tests/fusion_cases.json');
    destino.parent.createSync(recursive: true);
    destino.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'generatedBy': 'test/fusion_cases_test.dart',
        'note':
            'ARQUIVO GERADO. Nao editar a mao — rode o teste Dart para '
                'regenerar. Ele e a saida real da implementacao Dart, e o teste '
                'Python verifica que a implementacao de la produz o mesmo.',
        'cases': casos,
      }),
    );

    expect(casos, hasLength(FusionStrategy.values.length * entradas.length));
    expect(destino.existsSync(), isTrue);
  });
}
