import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:scorpions/data/mock/mock_species.dart';
import 'package:scorpions/data/models/app_user.dart';
import 'package:scorpions/data/models/captured_image.dart';
import 'package:scorpions/data/models/firestore_codec.dart';
import 'package:scorpions/data/models/identification.dart';
import 'package:scorpions/data/models/species.dart';

/// Exporta as formas de documento que o aplicativo realmente grava.
///
/// # Por que este arquivo existe
/// Os testes de Security Rules (em `firebase/test/`) usavam documentos escritos
/// à mão. Eles passavam — e mesmo assim o cadastro estava quebrado: o mapa que
/// o Dart produzia não trazia `role`, e a regra exige `role == 'user'`. Um
/// teste verde de um lado, um `permission-denied` garantido do outro.
///
/// A causa é conhecida: quando o teste inventa o dado, ele testa a si mesmo.
/// Este arquivo elimina a invenção — ele **gera** as formas a partir dos
/// modelos de produção e as grava em `firebase/test/contract-shapes.json`, que
/// os testes de regras então consomem.
///
/// Se um campo mudar no Dart e quebrar uma regra, agora um teste falha.
void main() {
  test('exporta as formas de documento para os testes de regras', () async {
    final DateTime fixedDate = DateTime.utc(2026, 9, 8, 12);

    // -- users/{uid} ----------------------------------------------------------
    const AppUser user = AppUser(
      id: 'uid-alice',
      name: 'Alice',
      email: 'alice@exemplo.test',
    );

    // -- identifications/{id}: identificada -----------------------------------
    final IdentificationResult identified = IdentificationResult.identified(
      id: 'ident-1',
      image: CapturedImage.simulated(),
      isMock: true,
      createdAt: fixedDate,
      predictions: <SpeciesPrediction>[
        SpeciesPrediction(species: MockSpecies.tityusSerrulatus, score: 0.94),
        SpeciesPrediction(species: MockSpecies.tityusBahiensis, score: 0.04),
      ],
    ).copyWith(userId: 'uid-alice', imageUrl: 'users/uid-alice/x/original.jpg');

    // -- identifications/{id}: rejeitada --------------------------------------
    final IdentificationResult rejected = IdentificationResult.rejected(
      id: 'ident-2',
      image: CapturedImage.simulated(),
      createdAt: fixedDate,
      reason: RejectionReason.noScorpionDetected,
    ).copyWith(userId: 'uid-alice');

    // -- species/{id} ---------------------------------------------------------
    final Species species = MockSpecies.tityusSerrulatus;

    final Map<String, Object?> shapes = <String, Object?>{
      '_comment': 'Gerado por test/contract_shapes_test.dart. Não editar à mão.',
      'userCreate': _encode(user.toCreateMap()),
      'userUpdate': _encode(user.toUpdateMap()),
      'identificationIdentified': _encode(identified.toMap()),
      'identificationRejected': _encode(rejected.toMap()),
      'species': _encode(species.toMap()),
    };

    final File output =
        File('firebase/test/contract-shapes.json');
    await output.parent.create(recursive: true);
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(shapes)}\n',
    );

    // Conferências que valem por si, mesmo sem o lado Node.
    final Map<String, Object?> userCreate =
        shapes['userCreate']! as Map<String, Object?>;

    // O bug que este arquivo nasceu para impedir.
    expect(
      userCreate['role'],
      'user',
      reason: 'A regra de criação exige role == "user"; omitir o campo faz '
          'todo cadastro falhar com permission-denied.',
    );
    expect(userCreate['uid'], 'uid-alice');
    expect(userCreate['createdAt'], '__SERVER_TIMESTAMP__');

    final Map<String, Object?> identMap =
        shapes['identificationIdentified']! as Map<String, Object?>;
    expect(identMap['userId'], 'uid-alice');
    expect(identMap['status'], 'identified');
    expect(identMap['modelVersion'], 'mock-v1');
    expect(identMap['confidence'], closeTo(0.94, 0.0001));
  });
}

/// Converte o mapa para algo que o JSON aceita.
///
/// A sentinela de carimbo do servidor vira uma string reconhecível, que o lado
/// Node substitui por `serverTimestamp()` na hora de escrever.
Object? _encode(Object? value) {
  if (FirestoreCodec.isServerTimestamp(value)) return '__SERVER_TIMESTAMP__';
  if (value is Map) {
    return value.map((Object? k, Object? v) =>
        MapEntry<String, Object?>(k.toString(), _encode(v)));
  }
  if (value is List) return value.map(_encode).toList();
  if (value is DateTime) return value.toIso8601String();
  return value;
}
