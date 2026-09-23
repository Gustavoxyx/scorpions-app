import 'package:flutter_test/flutter_test.dart';

import 'package:scorpions/data/mock/mock_species.dart';
import 'package:scorpions/data/models/app_user.dart';
import 'package:scorpions/data/models/captured_image.dart';
import 'package:scorpions/data/models/firestore_codec.dart';
import 'package:scorpions/data/models/identification.dart';
import 'package:scorpions/data/models/identification_status.dart';
import 'package:scorpions/data/models/species.dart';
import 'package:scorpions/data/models/user_role.dart';

/// Testes da camada de dados (brief §39).
///
/// Rodam sem Firebase: os modelos são Dart puro e o `FirestoreCodec` converte
/// por comportamento, não por tipo do SDK. Essa é a razão prática de manter os
/// modelos desacoplados — o teste é instantâneo e não precisa de emulador.
void main() {
  group('FirestoreCodec', () {
    test('lê datas em todos os formatos que o banco devolve', () {
      final DateTime now = DateTime(2026, 9, 8, 14, 30);

      expect(FirestoreCodec.dateTime(now), now);
      expect(
        FirestoreCodec.dateTime(now.millisecondsSinceEpoch),
        now,
      );
      expect(FirestoreCodec.dateTime(now.toIso8601String()), now);
      expect(FirestoreCodec.dateTime(_FakeTimestamp(now)), now);
    });

    test('devolve nulo para lixo em vez de lançar', () {
      expect(FirestoreCodec.dateTime('não é data'), isNull);
      expect(FirestoreCodec.dateTime(<String>['lista']), isNull);
      expect(FirestoreCodec.dateTime(null), isNull);
    });

    test('leitores têm valor de queda para tipo inesperado', () {
      expect(FirestoreCodec.string(42), '');
      expect(FirestoreCodec.integer('abc'), 0);
      expect(FirestoreCodec.number(true), 0);
      expect(FirestoreCodec.stringList('não é lista'), isEmpty);
      expect(FirestoreCodec.boolean('sim'), isFalse);
    });

    test('converte número inteiro para double e vice-versa', () {
      expect(FirestoreCodec.number(1), 1.0);
      expect(FirestoreCodec.integer(2.7), 3);
    });
  });

  group('UserRole', () {
    test('valor desconhecido cai no papel menos privilegiado', () {
      // A regra que importa: um documento corrompido, ou de uma versão futura
      // do app, nunca pode resultar em privilégio elevado.
      expect(UserRole.fromId('superadmin'), UserRole.user);
      expect(UserRole.fromId(null), UserRole.user);
      expect(UserRole.fromId(42), UserRole.user);
      expect(UserRole.fromId(''), UserRole.user);
    });

    test('reconhece os papéis habilitados', () {
      expect(UserRole.fromId('admin'), UserRole.admin);
      expect(UserRole.fromId('user'), UserRole.user);
      expect(UserRole.admin.isAdmin, isTrue);
      expect(UserRole.user.isAdmin, isFalse);
    });

    test('papéis futuros existem mas estão desabilitados', () {
      expect(UserRole.researcher.enabled, isFalse);
      expect(UserRole.reviewer.enabled, isFalse);
    });
  });

  group('AppUser', () {
    test('lê o documento do Firestore', () {
      final AppUser user = AppUser.fromMap('uid-123', <String, dynamic>{
        'uid': 'uid-123',
        'name': 'Gustavo Nunes',
        'email': 'gustavo@exemplo.test',
        'role': 'admin',
        'createdAt': DateTime(2026, 1, 10),
      });

      expect(user.id, 'uid-123');
      expect(user.name, 'Gustavo Nunes');
      expect(user.role, UserRole.admin);
      expect(user.firstName, 'Gustavo');
      expect(user.initials, 'GN');
    });

    test('sobrevive a documento incompleto', () {
      final AppUser user = AppUser.fromMap('uid-1', <String, dynamic>{});
      expect(user.name, '');
      expect(user.role, UserRole.user);
      expect(user.memberSince, isNull);
    });

    // O cliente não decide o próprio papel: o mapa de criação não carrega
    // `role`, e as Security Rules o fixam em 'user'.
    test('o mapa de criação usa carimbo do servidor', () {
      const AppUser user = AppUser(
        id: 'uid-1',
        name: 'Alice',
        email: 'alice@exemplo.test',
      );
      final Map<String, Object?> map = user.toCreateMap();

      expect(map['uid'], 'uid-1');
      expect(FirestoreCodec.isServerTimestamp(map['createdAt']), isTrue);
      expect(FirestoreCodec.isServerTimestamp(map['updatedAt']), isTrue);
    });

    test('o mapa de atualização só muda o nome', () {
      const AppUser user = AppUser(
        id: 'uid-1',
        name: 'Alice',
        email: 'alice@exemplo.test',
      );
      expect(user.toUpdateMap().keys, containsAll(<String>['name', 'updatedAt']));
      expect(user.toUpdateMap().containsKey('role'), isFalse);
      expect(user.toUpdateMap().containsKey('email'), isFalse);
    });
  });

  group('IdentificationStatus', () {
    test('valor desconhecido vira erro, não um resultado válido', () {
      expect(IdentificationStatus.fromId('inventado'), IdentificationStatus.error);
      expect(IdentificationStatus.fromId(null), IdentificationStatus.error);
    });

    test('só identified e lowConfidence têm predição', () {
      expect(IdentificationStatus.identified.hasPrediction, isTrue);
      expect(IdentificationStatus.lowConfidence.hasPrediction, isTrue);
      expect(IdentificationStatus.rejected.hasPrediction, isFalse);
      expect(IdentificationStatus.processing.hasPrediction, isFalse);
      expect(IdentificationStatus.error.hasPrediction, isFalse);
    });
  });

  group('IdentificationResult', () {
    IdentificationResult buildIdentified(double score) {
      return IdentificationResult.identified(
        id: 'ident-1',
        image: CapturedImage.simulated(),
        isMock: true,
        predictions: <SpeciesPrediction>[
          SpeciesPrediction(
            species: MockSpecies.tityusSerrulatus,
            score: score,
          ),
          SpeciesPrediction(
            species: MockSpecies.tityusBahiensis,
            score: 0.03,
          ),
        ],
      );
    }

    // O status é derivado da confiança, não informado por quem chama: não há
    // como gravar "identified" com uma estimativa fraca.
    test('confiança alta produz status identified', () {
      expect(buildIdentified(0.94).status, IdentificationStatus.identified);
    });

    test('confiança baixa produz status lowConfidence', () {
      expect(buildIdentified(0.5).status, IdentificationStatus.lowConfidence);
    });

    test('rejeição produz status rejected e nenhuma predição', () {
      final IdentificationResult result = IdentificationResult.rejected(
        id: 'ident-2',
        image: CapturedImage.simulated(),
        reason: RejectionReason.noScorpionDetected,
      );
      expect(result.status, IdentificationStatus.rejected);
      expect(result.predictions, isEmpty);
      expect(result.isRejected, isTrue);
    });

    test('grava a versão do modelo', () {
      expect(buildIdentified(0.9).modelVersion, 'mock-v1');
      expect(buildIdentified(0.9).toMap()['modelVersion'], 'mock-v1');
    });

    test('ida e volta pelo mapa preserva o essencial', () {
      final IdentificationResult original =
          buildIdentified(0.91).copyWith(userId: 'uid-1', imageUrl: 'users/x/y');
      final Map<String, Object?> map = original.toMap();

      // Simula o que o servidor devolve: o carimbo já resolvido.
      final Map<String, dynamic> stored = Map<String, dynamic>.from(map)
        ..['createdAt'] = original.createdAt;

      final IdentificationResult restored =
          IdentificationResult.fromMap(original.id, stored);

      expect(restored.id, original.id);
      expect(restored.userId, 'uid-1');
      expect(restored.imageUrl, 'users/x/y');
      expect(restored.status, original.status);
      expect(restored.modelVersion, original.modelVersion);
      expect(restored.top.species.scientificName, 'Tityus serrulatus');
      expect(restored.top.score, closeTo(0.91, 0.0001));
      expect(restored.alternatives, hasLength(1));
    });

    test('a rejeição sobrevive à ida e volta', () {
      final IdentificationResult original = IdentificationResult.rejected(
        id: 'ident-3',
        image: CapturedImage.simulated(),
        reason: RejectionReason.outOfDomain,
      );
      final Map<String, dynamic> stored =
          Map<String, dynamic>.from(original.toMap())
            ..['createdAt'] = original.createdAt;

      final IdentificationResult restored =
          IdentificationResult.fromMap(original.id, stored);

      expect(restored.isRejected, isTrue);
      expect(restored.rejectionReason, RejectionReason.outOfDomain);
    });

    test('documento sem espécie denormalizada não quebra', () {
      final IdentificationResult restored =
          IdentificationResult.fromMap('x', <String, dynamic>{
        'userId': 'uid-1',
        'status': 'identified',
        'modelVersion': 'mock-v1',
        'confidence': 0.8,
        'scientificName': 'Tityus stigmurus',
        'speciesId': 'tityus-stigmurus',
      });

      expect(restored.top.species.scientificName, 'Tityus stigmurus');
      expect(restored.top.species.isSummaryOnly, isTrue);
    });
  });

  group('Species', () {
    test('ida e volta pelo mapa preserva os campos científicos', () {
      final Species original = MockSpecies.tityusSerrulatus;
      final Map<String, dynamic> stored =
          Map<String, dynamic>.from(original.toMap());

      final Species restored = Species.fromMap(original.id, stored);

      expect(restored.scientificName, original.scientificName);
      expect(restored.family, original.family);
      expect(restored.medicalRelevance, original.medicalRelevance);
      expect(restored.distribution, original.distribution);
      expect(restored.morphology.length, original.morphology.length);
      expect(restored.isSummaryOnly, isFalse);
    });

    // §41: a estrutura do 3D existe, o sistema não.
    test('model3dUrl é gravado como nulo nesta fase', () {
      expect(MockSpecies.tityusSerrulatus.toMap()['model3dUrl'], isNull);
      expect(MockSpecies.tityusSerrulatus.has3DModel, isFalse);
    });

    test('espécie parcial se identifica como tal', () {
      final Species summary = Species.summary(
        id: 'x',
        scientificName: 'Tityus sp.',
        commonName: 'Escorpião',
      );
      expect(summary.isSummaryOnly, isTrue);
    });

    test('relevância médica desconhecida não é inventada', () {
      expect(MedicalRelevance.fromId('gravissima'), MedicalRelevance.unknown);
      expect(MedicalRelevance.fromId(null), MedicalRelevance.unknown);
    });
  });

  group('CapturedImage', () {
    test('imagem remota sem URL cai para simulada', () {
      final CapturedImage image =
          CapturedImage.remote(url: null, capturedAt: DateTime(2026));
      expect(image.isSimulated, isTrue);
      expect(image.isUploadable, isFalse);
    });

    test('imagem remota com URL não é enviável de novo', () {
      final CapturedImage image = CapturedImage.remote(
        url: 'users/a/identifications/b/original.jpg',
        capturedAt: DateTime(2026),
      );
      expect(image.hasUrl, isTrue);
      expect(image.isUploadable, isFalse);
    });
  });
}

/// Imita o `Timestamp` do Firestore pelo comportamento (`toDate()`), que é
/// como o `FirestoreCodec` o reconhece — sem importar o SDK.
class _FakeTimestamp {
  const _FakeTimestamp(this._value);
  final DateTime _value;
  DateTime toDate() => _value;
}
