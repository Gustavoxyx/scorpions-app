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
    this.thumbnailUrl,
    this.imageQuality,
    this.errorCode,
    this.pipelineVersion = pipelineV1,
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

  /// Registro recém-criado, ainda sem análise (briefing Fase 4, §10).
  ///
  /// É o estado normal de toda identificação nesta fase: a imagem foi
  /// validada, medida, processada e enviada, e o modelo que responderia
  /// "qual espécie" ainda não existe. Gravar `processing` é a forma honesta
  /// de dizer isso — e é o estado que a Fase 5 vai encontrar para preencher.
  factory IdentificationResult.processing({
    required String id,
    required CapturedImage image,
    String? userId,
    String? imageUrl,
    String? thumbnailUrl,
    Map<String, Object?>? imageQuality,
    DateTime? createdAt,
  }) {
    return IdentificationResult._(
      id: id,
      image: image,
      createdAt: createdAt ?? DateTime.now(),
      predictions: const <SpeciesPrediction>[],
      rejectionReason: null,
      isMock: true,
      status: IdentificationStatus.processing,
      modelVersion: mockModelVersion,
      userId: userId,
      imageUrl: imageUrl,
      thumbnailUrl: thumbnailUrl,
      imageQuality: imageQuality,
    );
  }

  /// Versão do pipeline de imagem que produziu o registro (§26).
  ///
  /// Separada de [modelVersion] de propósito: são duas coisas que vão mudar
  /// em ritmos diferentes. Trocar o limiar de nitidez muda o pipeline sem
  /// tocar no modelo; trocar o classificador muda o modelo sem tocar no
  /// pipeline. Com um campo só, "reprocessar tudo que veio da versão X" vira
  /// uma pergunta sem resposta.
  static const String pipelineV1 = 'pipeline-v1';

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

  /// Caminho da miniatura. Existe para que abrir o histórico não baixe a
  /// imagem cheia de cada item.
  final String? thumbnailUrl;

  /// Medidas de qualidade da fotografia, como gravadas.
  ///
  /// Mapa opaco e não objeto tipado: aqui ele é registro, não regra. Guardar
  /// as medidas permite recalibrar limiares na Fase 6 e reavaliar o que já
  /// foi coletado sem pedir foto nova a ninguém.
  final Map<String, Object?>? imageQuality;

  /// Código técnico da falha, quando [status] é `error`. Nunca exibido.
  final String? errorCode;

  /// Versão do pipeline de imagem (§26).
  final String pipelineVersion;

  bool get isRejected => rejectionReason != null;

  SpeciesPrediction get top => predictions.first;

  List<SpeciesPrediction> get alternatives => predictions.skip(1).toList();

  ConfidenceLevel get level =>
      isRejected ? ConfidenceLevel.unidentified : top.level;

  IdentificationResult copyWith({
    String? userId,
    String? imageUrl,
    String? thumbnailUrl,
    CapturedImage? image,
    Map<String, Object?>? imageQuality,
    String? errorCode,
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
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      imageQuality: imageQuality ?? this.imageQuality,
      errorCode: errorCode ?? this.errorCode,
      pipelineVersion: pipelineVersion,
    );
  }

  // -- Serialização -----------------------------------------------------------

  /// Documento `identifications/{id}` (brief §11).
  ///
  /// `userId` é gravado e é o que as Security Rules conferem contra
  /// `request.auth.uid`. Sem ele, não há como um documento pertencer a alguém.
  /// O que o **cliente** tem direito de gravar.
  ///
  /// # Por que existe separado de [toMap]
  /// A auditoria de segurança (HIGH-1) encontrou que o aplicativo escrevia
  /// `confidence` e `modelVersion` direto no Firestore, e que a regra
  /// validava o formato, não a origem — um `0.99` forjado passava igual a um
  /// produzido por modelo.
  ///
  /// Sem IA o estrago era pequeno: o usuário poluía o próprio histórico. Com
  /// IA, um registro forjado contaminaria as métricas de acurácia, entraria
  /// na fila de revisão humana como se fosse saída do modelo, alimentaria o
  /// dataset de retreinamento com rótulo falso, e destruiria a auditabilidade
  /// do §39 — não haveria como distinguir o que o modelo disse do que o
  /// usuário digitou.
  ///
  /// # O que ficou de fora, e não é esquecimento
  /// `speciesId`, `scientificName`, `confidence`, `species`, `alternatives`,
  /// `rejectionReason` e `modelVersion`. Todos nascem no servidor agora.
  ///
  /// A Security Rules recusa quem tentar escrevê-los mesmo assim — **ela** é
  /// a proteção, não este método. Mas o que o cliente não consegue nomear,
  /// ele não consegue forjar por distração, e as duas camadas dizendo a mesma
  /// coisa é o que o briefing chama de defesa em profundidade.
  Map<String, Object?> toClientCreateMap() => <String, Object?>{
        'userId': userId,
        'imageUrl': imageUrl,
        'thumbnailUrl': thumbnailUrl,
        // Só este estado. Os outros são conclusões da análise, e a análise
        // não acontece aqui.
        'status': IdentificationStatus.processing.id,
        'pipelineVersion': pipelineVersion,
        'imageQuality': imageQuality,
        'errorCode': errorCode,
        'createdAt': FirestoreCodec.serverTimestamp,
      };

  /// Documento completo, incluindo o que só o servidor grava.
  ///
  /// Usado para ler, para auditar e pelo backend de inferência. **Não** é o
  /// que o aplicativo envia numa criação — para isso existe
  /// [toClientCreateMap].
  Map<String, Object?> toMap() => <String, Object?>{
        'userId': userId,
        'imageUrl': imageUrl,
        'thumbnailUrl': thumbnailUrl,
        'status': status.id,
        'modelVersion': modelVersion,
        'pipelineVersion': pipelineVersion,
        'imageQuality': imageQuality,
        'errorCode': errorCode,
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
    final String? thumbnailUrl =
        FirestoreCodec.stringOrNull(map['thumbnailUrl']);
    final Map<String, dynamic> qualidade =
        FirestoreCodec.map(map['imageQuality']);
    final Map<String, Object?>? imageQuality =
        qualidade.isEmpty ? null : Map<String, Object?>.from(qualidade);
    final String? errorCode = FirestoreCodec.stringOrNull(map['errorCode']);
    final String pipelineVersion = FirestoreCodec.string(
      map['pipelineVersion'],
      fallback: pipelineV1,
    );

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
        thumbnailUrl: thumbnailUrl,
        imageQuality: imageQuality,
        errorCode: errorCode,
        pipelineVersion: pipelineVersion,
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
      thumbnailUrl: thumbnailUrl,
      imageQuality: imageQuality,
      errorCode: errorCode,
      pipelineVersion: pipelineVersion,
    );
  }
}
