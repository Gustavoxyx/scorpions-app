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
      // O que o aplicativo REALMENTE envia numa criação. É esta forma que
      // precisa ser aceita pelas regras.
      'identificationClientCreate': _encode(identified.toClientCreateMap()),

      // O documento completo, com os campos que só o servidor escreve.
      // Exportado de propósito para o lado oposto do teste: as regras
      // precisam RECUSAR esta forma quando ela vem do cliente (HIGH-1).
      'identificationServerFull': _encode(identified.toMap()),
      'identificationRejectedServerFull': _encode(rejected.toMap()),
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

    // A forma do cliente: o que o aplicativo realmente envia numa criação.
    final Map<String, Object?> clienteMap =
        shapes['identificationClientCreate']! as Map<String, Object?>;
    expect(clienteMap['userId'], 'uid-alice');
    expect(clienteMap['status'], 'processing',
        reason: 'a criação nasce sempre em processing; os outros estados são '
            'conclusões de uma análise que não acontece no aplicativo');

    // E o que ela NÃO pode conter. Esta verificação é o HIGH-1 travado na
    // origem: se alguém devolver um desses campos ao mapa do cliente, o teste
    // cai aqui, antes mesmo de as regras serem consultadas.
    for (final String proibido in <String>[
      'confidence',
      'speciesId',
      'scientificName',
      'modelVersion',
      'species',
      'alternatives',
      'rejectionReason',
    ]) {
      expect(clienteMap.containsKey(proibido), isFalse,
          reason: '"$proibido" nasce no servidor — ver SECURITY_AUDIT HIGH-1');
    }

    // A forma completa continua existindo, para o servidor e para auditoria.
    final Map<String, Object?> servidorMap =
        shapes['identificationServerFull']! as Map<String, Object?>;
    expect(servidorMap['confidence'], closeTo(0.94, 0.0001));
    expect(servidorMap['modelVersion'], 'mock-v1');
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
