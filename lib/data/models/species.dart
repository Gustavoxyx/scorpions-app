import 'package:flutter/foundation.dart';

import 'firestore_codec.dart';
import 'species_model_3d.dart';

/// Grau de relevância médica registrado na literatura para o gênero/espécie.
///
/// É um rótulo de catálogo, NUNCA um diagnóstico. A UI acompanha este campo
/// obrigatoriamente de um aviso (ver `AppStrings.medicalDisclaimer`).
enum MedicalRelevance {
  significant('significant'),
  moderate('moderate'),
  low('low'),
  unknown('unknown');

  const MedicalRelevance(this.id);

  /// Valor persistido, independente do nome do membro em Dart.
  final String id;

  String get label => switch (this) {
        MedicalRelevance.significant => 'Relevância significativa',
        MedicalRelevance.moderate => 'Relevância moderada',
        MedicalRelevance.low => 'Baixa relevância',
        MedicalRelevance.unknown => 'Não documentada',
      };

  /// Desconhecido vira [unknown] — nunca inventa uma relevância que não foi
  /// afirmada pela fonte.
  static MedicalRelevance fromId(Object? raw) {
    if (raw is! String) return MedicalRelevance.unknown;
    for (final MedicalRelevance value in MedicalRelevance.values) {
      if (value.id == raw) return value;
    }
    return MedicalRelevance.unknown;
  }
}

/// Uma estrutura morfológica destacável.
///
/// Na Fase 7 esta lista alimenta um diagrama interativo; por ora é conteúdo
/// textual com um ícone.
@immutable
class MorphologyFeature {
  const MorphologyFeature({
    required this.name,
    required this.description,
  });

  factory MorphologyFeature.fromMap(Map<String, dynamic> map) {
    return MorphologyFeature(
      name: FirestoreCodec.string(map['name']),
      description: FirestoreCodec.string(map['description']),
    );
  }

  final String name;
  final String description;

  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        'description': description,
      };
}

/// Espécie do catálogo científico.
///
/// Modelo puro: sem dependência de Firestore, de rede ou de widgets. Na Fase 3
/// ganha `fromMap`/`toMap` e passa a ser hidratado pelo `FirestoreSpecies-
/// Repository` sem que a UI perceba.
@immutable
class Species {
  const Species({
    required this.id,
    required this.scientificName,
    required this.commonName,
    required this.family,
    required this.genus,
    required this.specificEpithet,
    required this.summary,
    required this.sizeRange,
    required this.coloration,
    required this.behaviour,
    required this.distribution,
    required this.habitats,
    required this.medicalRelevance,
    required this.medicalNotes,
    required this.morphology,
    required this.accentSeed,
    this.imageAsset,
    this.model3D,
  });

  final String id;
  final String scientificName;
  final String commonName;
  final String family;
  final String genus;
  final String specificEpithet;

  /// Parágrafo curto exibido no resultado e no topo da ficha.
  final String summary;

  final String sizeRange;
  final String coloration;
  final String behaviour;

  /// Regiões de ocorrência em texto. O mapa real entra na Fase 7.
  final List<String> distribution;
  final List<String> habitats;

  final MedicalRelevance medicalRelevance;
  final String medicalNotes;
  final List<MorphologyFeature> morphology;

  /// Semente determinística usada para gerar a arte do placeholder da espécie.
  /// Evita depender de arquivos de imagem nesta fase.
  final int accentSeed;

  /// Reservado para a Fase 7, quando houver fotografias licenciadas.
  final String? imageAsset;

  /// Modelo tridimensional da espécie.
  ///
  /// Nulo em toda a Fase 2 — nenhum arquivo 3D foi empacotado. O campo existe
  /// para que a UI já pergunte [has3DModel] e as telas de resultado e de ficha
  /// não precisem ser reconstruídas quando os modelos chegarem.
  final SpeciesModel3D? model3D;

  /// Se `false`, as telas mostram o espaço reservado ao 3D em estado inativo,
  /// com aviso honesto, em vez de esconder a funcionalidade.
  bool get has3DModel => model3D != null;

  String get distributionSummary => distribution.join(' · ');

  /// Texto de busca do catálogo, normalizado sem acentos.
  String get searchIndex => <String>[
        scientificName,
        commonName,
        family,
        genus,
        ...distribution,
      ].join(' ').toLowerCase();

  // -- Serialização -----------------------------------------------------------

  /// Lê o documento `species/{id}`.
  factory Species.fromMap(String id, Map<String, dynamic> map) {
    return Species(
      id: id,
      scientificName: FirestoreCodec.string(map['scientificName']),
      commonName: FirestoreCodec.string(map['commonName']),
      family: FirestoreCodec.string(map['family']),
      genus: FirestoreCodec.string(map['genus']),
      specificEpithet: FirestoreCodec.string(map['specificEpithet']),
      summary: FirestoreCodec.string(map['summary']),
      sizeRange: FirestoreCodec.string(map['sizeRange']),
      coloration: FirestoreCodec.string(map['coloration']),
      behaviour: FirestoreCodec.string(map['behaviour']),
      distribution: FirestoreCodec.stringList(map['distribution']),
      habitats: FirestoreCodec.stringList(map['habitats']),
      medicalRelevance: MedicalRelevance.fromId(map['medicalRelevance']),
      medicalNotes: FirestoreCodec.string(map['medicalNotes']),
      morphology: FirestoreCodec.mapList(map['morphology'])
          .map(MorphologyFeature.fromMap)
          .toList(growable: false),
      accentSeed: FirestoreCodec.integer(map['accentSeed']),
      imageAsset: FirestoreCodec.stringOrNull(map['imageUrl']),
      // Fase 3: `model3dUrl` é lido mas nunca preenchido — a estrutura existe,
      // o visualizador não (§41). Quando existir, basta o documento trazer a
      // URL e construir o SpeciesModel3D aqui.
      model3D: null,
    );
  }

  /// Espécie **parcial**, montada a partir dos campos denormalizados dentro de
  /// uma identificação.
  ///
  /// # Por que isto existe
  /// O documento de identificação guarda só `speciesId`, `scientificName` e
  /// `commonName`. Isso é suficiente para desenhar um cartão de histórico, e
  /// evita uma leitura extra por item — numa lista de 50 registros, seriam 50
  /// leituras cobradas para mostrar dois textos.
  ///
  /// Os demais campos ficam vazios de propósito. Ao abrir a ficha completa, a
  /// tela carrega o documento real de `species/{id}`.
  factory Species.summary({
    required String id,
    required String scientificName,
    required String commonName,
  }) {
    return Species(
      id: id,
      scientificName: scientificName,
      commonName: commonName,
      family: '',
      genus: '',
      specificEpithet: '',
      summary: '',
      sizeRange: '',
      coloration: '',
      behaviour: '',
      distribution: const <String>[],
      habitats: const <String>[],
      medicalRelevance: MedicalRelevance.unknown,
      medicalNotes: '',
      morphology: const <MorphologyFeature>[],
      accentSeed: id.hashCode.abs() % 256,
    );
  }

  /// `true` quando esta instância veio de [Species.summary] e portanto não tem
  /// conteúdo científico — a ficha precisa buscar o documento completo.
  bool get isSummaryOnly => family.isEmpty && summary.isEmpty;

  /// Campos denormalizados gravados dentro de uma identificação.
  Map<String, Object?> toSummaryMap() => <String, Object?>{
        'id': id,
        'scientificName': scientificName,
        'commonName': commonName,
      };

  /// Documento completo, para semear o catálogo.
  Map<String, Object?> toMap() => <String, Object?>{
        'scientificName': scientificName,
        'commonName': commonName,
        'family': family,
        'genus': genus,
        'specificEpithet': specificEpithet,
        'summary': summary,
        'sizeRange': sizeRange,
        'coloration': coloration,
        'behaviour': behaviour,
        'distribution': distribution,
        'habitats': habitats,
        'medicalRelevance': medicalRelevance.id,
        'medicalNotes': medicalNotes,
        'morphology': morphology
            .map((MorphologyFeature f) => f.toMap())
            .toList(growable: false),
        'accentSeed': accentSeed,
        'imageUrl': imageAsset,
        // Reservado (§10, §41). Sempre nulo nesta fase.
        'model3dUrl': null,
        'createdAt': FirestoreCodec.serverTimestamp,
        'updatedAt': FirestoreCodec.serverTimestamp,
      };
}
