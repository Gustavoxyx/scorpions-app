import 'package:flutter/foundation.dart';

import 'captured_image.dart';
import 'confidence_level.dart';
import 'firestore_codec.dart';
import 'identification_status.dart';
import 'species.dart';

/// Motivo pelo qual o sistema se recusou a responder.
///
/// Existe desde já para que a Fase 6 tenha onde encaixar os sinais reais do
/// modelo (nitidez, enquadramento, ausência de alvo, espécie fora do domínio).
enum RejectionReason {
  lowImageQuality('low_image_quality'),
  noScorpionDetected('no_scorpion_detected'),
  outOfDomain('out_of_domain'),
  ambiguous('ambiguous');

  const RejectionReason(this.id);

  /// Valor persistido, independente do nome do membro em Dart.
  final String id;

  /// Desconhecido cai em [lowImageQuality]: é o motivo mais provável e o que
  /// gera a orientação mais útil ("tente outra foto").
  static RejectionReason fromId(Object? raw) {
    if (raw is! String) return RejectionReason.lowImageQuality;
    for (final RejectionReason reason in RejectionReason.values) {
      if (reason.id == raw) return reason;
    }
    return RejectionReason.lowImageQuality;
  }

  String get title => switch (this) {
        RejectionReason.lowImageQuality => 'Qualidade da imagem',
        RejectionReason.noScorpionDetected => 'Nenhum escorpião detectado',
        RejectionReason.outOfDomain => 'Fora do catálogo conhecido',
        RejectionReason.ambiguous => 'Características ambíguas',
      };

  String get hint => switch (this) {
        RejectionReason.lowImageQuality =>
          'A foto pode estar desfocada, escura ou muito distante.',
        RejectionReason.noScorpionDetected =>
          'Não encontramos um escorpião no enquadramento.',
        RejectionReason.outOfDomain =>
          'O animal não corresponde às espécies do catálogo atual.',
        RejectionReason.ambiguous =>
          'Duas ou mais espécies ficaram igualmente prováveis.',
      };
}

/// Uma hipótese do classificador.
@immutable
class SpeciesPrediction {
  const SpeciesPrediction({required this.species, required this.score});

  final Species species;

  /// Probabilidade bruta, de 0 a 1.
  final double score;

  ConfidenceLevel get level => ConfidenceLevel.fromScore(score);
}

/// Saída do `IdentificationService` e espelho de `identifications/{id}`.
///
/// Um resultado é OU uma identificação com hipóteses ordenadas, OU uma
/// rejeição explícita. Não existe estado intermediário silencioso.
///
/// # Sobre a imagem
/// [image] é a imagem local (arquivo no aparelho); [imageUrl] é o caminho no
/// Cloud Storage depois do upload. Os dois coexistem de propósito: logo após a
/// captura só existe o arquivo local, e a tela precisa mostrar algo antes de o
/// upload terminar. Ao reabrir do histórico só existe a URL.
@immutable
class IdentificationResult {
  const IdentificationResult._({
    required this.id,
    required this.image,
    required this.createdAt,
    required this.predictions,
    required this.rejectionReason,
    required this.isMock,
    required this.status,
    required this.modelVersion,
    required this.userId,
    required this.imageUrl,
  });

  factory IdentificationResult.identified({
    required String id,
    required CapturedImage image,
    required List<SpeciesPrediction> predictions,
    DateTime? createdAt,
    bool isMock = false,
    String modelVersion = mockModelVersion,
    String? userId,
    String? imageUrl,
  }) {
    assert(
      predictions.isNotEmpty,
      'Um resultado identificado precisa de hipóteses.',
    );
    final ConfidenceLevel level = predictions.first.level;
    return IdentificationResult._(
      id: id,
      image: image,
      createdAt: createdAt ?? DateTime.now(),
      predictions: List<SpeciesPrediction>.unmodifiable(predictions),
      rejectionReason: null,
      isMock: isMock,
      // O status é derivado da confiança, não informado por quem chama: assim
      // não há como gravar "identified" com uma estimativa fraca.
      status: level == ConfidenceLevel.low
          ? IdentificationStatus.lowConfidence
          : IdentificationStatus.identified,
      modelVersion: modelVersion,
      userId: userId,
      imageUrl: imageUrl,
    );
  }

  factory IdentificationResult.rejected({
    required String id,
    required CapturedImage image,
    required RejectionReason reason,
    DateTime? createdAt,
    bool isMock = false,
    String modelVersion = mockModelVersion,
    String? userId,
    String? imageUrl,
  }) {
    return IdentificationResult._(
      id: id,
      image: image,
      createdAt: createdAt ?? DateTime.now(),
      predictions: const <SpeciesPrediction>[],
      rejectionReason: reason,
      isMock: isMock,
      status: IdentificationStatus.rejected,
      modelVersion: modelVersion,
      userId: userId,
      imageUrl: imageUrl,
    );
  }

  /// Versão do motor de identificação usada nesta fase (brief §13).
  ///
  /// Gravar isto desde já é o que vai permitir, quando o modelo real existir,
  /// responder a perguntas como "este resultado ruim veio de qual versão?" e
  /// reprocessar seletivamente o que foi gerado por uma versão específica.
  static const String mockModelVersion = 'mock-v1';

  final String id;

  /// Imagem local. Nula em registros vindos do banco.
  final CapturedImage image;

  final DateTime createdAt;

  /// Ordenadas da mais provável para a menos provável.
  final List<SpeciesPrediction> predictions;

  final RejectionReason? rejectionReason;

  /// Enquanto a IA real não existir, sempre `true`: a UI exibe o selo de dado
  /// simulado.
  final bool isMock;

  /// Estado do ciclo de vida (§12).
  final IdentificationStatus status;

  /// Identificador da versão do modelo que produziu o resultado (§13).
  final String modelVersion;

  /// Dono do registro. Nulo enquanto o resultado só existe em memória.
  final String? userId;

  /// Caminho no Cloud Storage, depois do upload.
  final String? imageUrl;

  bool get isRejected => rejectionReason != null;

  SpeciesPrediction get top => predictions.first;

  List<SpeciesPrediction> get alternatives => predictions.skip(1).toList();

  ConfidenceLevel get level =>
      isRejected ? ConfidenceLevel.unidentified : top.level;

  IdentificationResult copyWith({
    String? userId,
    String? imageUrl,
    CapturedImage? image,
  }) {
    return IdentificationResult._(
      id: id,
      image: image ?? this.image,
      createdAt: createdAt,
      predictions: predictions,
      rejectionReason: rejectionReason,
      isMock: isMock,
      status: status,
      modelVersion: modelVersion,
      userId: userId ?? this.userId,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  // -- Serialização -----------------------------------------------------------

  /// Documento `identifications/{id}` (brief §11).
  ///
  /// `userId` é gravado e é o que as Security Rules conferem contra
  /// `request.auth.uid`. Sem ele, não há como um documento pertencer a alguém.
  Map<String, Object?> toMap() => <String, Object?>{
        'userId': userId,
        'imageUrl': imageUrl,
        'status': status.id,
        'modelVersion': modelVersion,
        'isMock': isMock,
        'createdAt': FirestoreCodec.serverTimestamp,

        // Campos de topo da hipótese principal: permitem consultar e ordenar
        // sem abrir o mapa aninhado.
        'speciesId': isRejected ? null : top.species.id,
        'scientificName': isRejected ? null : top.species.scientificName,
        'confidence': isRejected ? null : top.score,
        'rejectionReason': rejectionReason?.id,

        // Espécie denormalizada: evita uma leitura por item na lista de
        // histórico (ver `Species.summary`).
        'species': isRejected ? null : top.species.toSummaryMap(),

        // Hipóteses alternativas, para a seção "outras possibilidades".
        'alternatives': alternatives
            .map((SpeciesPrediction p) => <String, Object?>{
                  ...p.species.toSummaryMap(),
                  'confidence': p.score,
                })
            .toList(growable: false),
      };

  /// Reconstrói a partir do documento.
  ///
  /// As espécies vêm **parciais** (só os campos denormalizados). Isso basta
  /// para as listas; a ficha completa carrega o documento de `species/{id}`.
  factory IdentificationResult.fromMap(String id, Map<String, dynamic> map) {
    final IdentificationStatus status =
        IdentificationStatus.fromId(map['status']);
    final DateTime createdAt = FirestoreCodec.dateTimeOrNow(map['createdAt']);
    final String modelVersion = FirestoreCodec.string(
      map['modelVersion'],
      fallback: mockModelVersion,
    );
    final bool isMock = FirestoreCodec.boolean(map['isMock'], fallback: true);
    final String? userId = FirestoreCodec.stringOrNull(map['userId']);
    final String? imageUrl = FirestoreCodec.stringOrNull(map['imageUrl']);

    // A imagem local não existe num registro vindo do banco; a tela usa a URL.
    final CapturedImage image = CapturedImage.remote(
      url: imageUrl,
      capturedAt: createdAt,
    );

    if (!status.hasPrediction) {
      return IdentificationResult._(
        id: id,
        image: image,
        createdAt: createdAt,
        predictions: const <SpeciesPrediction>[],
        rejectionReason: RejectionReason.fromId(map['rejectionReason']),
        isMock: isMock,
        status: status,
        modelVersion: modelVersion,
        userId: userId,
        imageUrl: imageUrl,
      );
    }

    final Map<String, dynamic> speciesMap = FirestoreCodec.map(map['species']);
    final List<SpeciesPrediction> predictions = <SpeciesPrediction>[
      SpeciesPrediction(
        species: Species.summary(
          id: FirestoreCodec.string(
            speciesMap['id'],
            fallback: FirestoreCodec.string(map['speciesId']),
          ),
          scientificName: FirestoreCodec.string(
            speciesMap['scientificName'],
            fallback: FirestoreCodec.string(map['scientificName']),
          ),
          commonName: FirestoreCodec.string(speciesMap['commonName']),
        ),
        score: FirestoreCodec.number(map['confidence']),
      ),
      for (final Map<String, dynamic> alt
          in FirestoreCodec.mapList(map['alternatives']))
        SpeciesPrediction(
          species: Species.summary(
            id: FirestoreCodec.string(alt['id']),
            scientificName: FirestoreCodec.string(alt['scientificName']),
            commonName: FirestoreCodec.string(alt['commonName']),
          ),
          score: FirestoreCodec.number(alt['confidence']),
        ),
    ];

    return IdentificationResult._(
      id: id,
      image: image,
      createdAt: createdAt,
      predictions: List<SpeciesPrediction>.unmodifiable(predictions),
      rejectionReason: null,
      isMock: isMock,
      status: status,
      modelVersion: modelVersion,
      userId: userId,
      imageUrl: imageUrl,
    );
  }
}
