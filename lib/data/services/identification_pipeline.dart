import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/observability/app_log.dart';
import '../models/captured_image.dart';
import '../models/classification.dart';
import '../models/detection.dart';
import '../models/identification.dart';
import '../models/processed_image.dart';
import '../repositories/auth_repository.dart';
import '../repositories/identification_repository.dart';
import 'connectivity_service.dart';
import 'failure.dart';
import 'image_bytes_reader.dart';
import 'image_processing_service.dart';
import 'image_upload_service.dart';
import 'scorpion_detection_service.dart';
import 'species_classification_service.dart';

/// Etapas visíveis do pipeline (briefing Fase 4, §15).
///
/// # Por que são cinco e não as seis da lista do briefing
/// Validar, medir qualidade e processar acontecem numa **única** decodificação
/// — é a diferença entre o aplicativo responder e travar num aparelho de
/// entrada. Mostrar três rótulos para um trabalho que acontece de uma vez só
/// seria encenação: o texto mudaria sozinho enquanto nada distinto estaria
/// acontecendo. Preferimos um rótulo honesto para um passo real.
enum PipelineStage {
  reading('Preparando imagem…', 'Lendo o arquivo da fotografia'),
  inspecting(
    'Verificando qualidade…',
    'Conferindo formato, resolução, luz e nitidez',
  ),
  registering(
    'Registrando identificação…',
    'Criando o registro no seu histórico',
  ),
  uploading(
    'Enviando imagem…',
    'Transferindo original, versão de análise e miniatura',
  ),
  awaitingAnalysis(
    'Preparando análise…',
    'A identificação por modelo entra na próxima fase',
  );

  const PipelineStage(this.label, this.detail);

  final String label;
  final String detail;
}

/// Desfecho de uma submissão.
@immutable
class PipelineOutcome {
  const PipelineOutcome._({required this.result, required this.cancelled});

  const PipelineOutcome.completed(IdentificationResult result)
      : this._(result: result, cancelled: false);

  const PipelineOutcome.cancelled() : this._(result: null, cancelled: true);

  final IdentificationResult? result;
  final bool cancelled;
}

/// Coordena a jornada da imagem, da leitura ao registro (briefing §11).
///
/// # Por que existe
/// Sem ele, essa sequência moraria na tela — e a tela passaria a saber sobre
/// Storage, Firestore, isolates e sessão de usuário. O §11 pede o contrário: a
/// interface chama o pipeline e observa etapas.
///
/// # Duas fases, e não uma
/// [prepare] e [submit] são separados de propósito. Entre os dois existe uma
/// decisão humana: se a foto saiu ruim, o §6 manda **perguntar** antes de
/// gastar a rede do usuário. Um `run()` único não teria onde encaixar essa
/// pergunta sem receber um callback de confirmação — o que seria a mesma
/// separação, disfarçada.
///
/// # De onde vem o dono do registro
/// De [AuthRepository.currentUser], nunca de parâmetro (§9 e §20). Um `userId`
/// recebido de fora permitiria à interface pedir para escrever na pasta de
/// outra pessoa. As regras recusariam — mas o pedido não deve nem ser possível
/// de formular.
class IdentificationPipeline {
  IdentificationPipeline({
    required this._auth,
    required this._repository,
    required this._processing,
    required this._uploader,
    required this._connectivity,
    this.detector = const MockScorpionDetectionService(),
    this.classifier = const MockSpeciesClassificationService(),
  });

  final AuthRepository _auth;
  final IdentificationRepository _repository;
  final ImageProcessingService _processing;
  final ImageUploadService _uploader;
  final ConnectivityService _connectivity;

  /// Contratos da Fase 5. Públicos porque um teste precisa poder trocar o
  /// dublê sem reconstruir o pipeline inteiro.
  final ScorpionDetectionService detector;
  final SpeciesClassificationService classifier;

  bool _cancelled = false;

  /// Interrompe a submissão em andamento (§18).
  ///
  /// Não aborta um envio já em voo — o SDK do Storage não oferece isso de
  /// forma confiável em todas as plataformas. O que faz é parar antes da
  /// próxima etapa e **apagar o que já subiu**, para não deixar arquivo órfão
  /// ocupando o bucket sem registro que o referencie.
  void cancel() => _cancelled = true;

  /// Lê, valida, mede e deriva as três formas. Uma decodificação só.
  ///
  /// Não lança por imagem ruim: uma recusa é um resultado que a tela precisa
  /// exibir, não uma exceção que ela precisa capturar.
  Future<ImagePreparation> prepare(CapturedImage image) async {
    _cancelled = false;
    AppLog.event(AppEvent.imageSelected, <String, Object?>{
      'source': image.source.name,
    });

    // Sem arquivo por trás não há o que preparar. Tentar ler os bytes aqui
    // transformaria o modo de demonstração num erro de leitura.
    if (!image.isUploadable) return ImagePreparation.simulated();

    final Uint8List bytes = await readImageBytes(image);
    AppLog.event(AppEvent.imageProcessingStarted, <String, Object?>{
      'kb': (bytes.length / 1024).round(),
    });

    final ImagePreparation p = await _processing.prepare(bytes);

    if (!p.isValid) {
      AppLog.event(AppEvent.imageValidationFailed, <String, Object?>{
        'code': p.validation.code.name,
      });
      return p;
    }

    AppLog.event(AppEvent.imageQualityChecked, <String, Object?>{
      'quality': p.quality!.quality.name,
      'score': double.parse(p.quality!.score.toStringAsFixed(3)),
      'warnings': p.quality!.warnings.length,
    });
    AppLog.event(AppEvent.imageProcessingCompleted, <String, Object?>{
      'kb': (p.image!.totalBytes / 1024).round(),
      'reencoded': p.image!.originalWasReencoded,
    });
    return p;
  }

  /// Cria o registro, envia as imagens e devolve a identificação em
  /// `processing` — que é o estado honesto enquanto não há modelo (§10).
  Future<PipelineOutcome> submit({
    required CapturedImage image,
    required ImagePreparation preparation,
    void Function(PipelineStage stage)? onStage,
  }) async {
    assert(preparation.canProceed, 'submit exige uma preparação utilizável');

    final ProcessedImage? processada = preparation.image;
    final String uid = _requireUid();
    final String id = newId();

    if (!await _connectivity.hasConnection()) {
      throw const AppFailure(
        kind: FailureKind.network,
        message: 'Você está offline. Conecte-se para enviar a fotografia.',
        code: 'offline',
      );
    }

    onStage?.call(PipelineStage.registering);
    if (_cancelled) return _abortar(uid, id, apagar: false);

    IdentificationResult registro = IdentificationResult.processing(
      id: id,
      image: image,
      userId: uid,
      imageQuality: preparation.quality?.toMap(),
    );
    await _repository.save(registro);
    AppLog.event(AppEvent.identificationCreated, <String, Object?>{
      'quality': preparation.quality?.quality.name ?? 'simulada',
    });

    if (processada != null) {
      onStage?.call(PipelineStage.uploading);
      if (_cancelled) return _abortar(uid, id);

      AppLog.event(AppEvent.uploadStarted, <String, Object?>{
        'kb': (processada.totalBytes / 1024).round(),
      });
      final UploadedImagePaths caminhos = await _uploader.uploadAll(
        image: processada,
        userId: uid,
        identificationId: id,
      );
      AppLog.event(AppEvent.uploadCompleted, <String, Object?>{
        'files': caminhos.uploadedCount,
      });

      if (_cancelled) return _abortar(uid, id);

      // A referência gravada aponta para a versão de análise, com queda para
      // o original: é ela que um modelo vai consumir.
      registro = registro.copyWith(
        imageUrl: caminhos.forAnalysis,
        thumbnailUrl: caminhos.thumbnail,
      );
      await _repository.attachImages(
        id,
        imageUrl: caminhos.forAnalysis,
        thumbnailUrl: caminhos.thumbnail,
      );
    }

    onStage?.call(PipelineStage.awaitingAnalysis);
    if (processada != null) await _prepararAnalise(processada);

    return PipelineOutcome.completed(registro);
  }

  // -- Interno ----------------------------------------------------------------

  /// Chama os contratos da Fase 5 já no lugar certo do fluxo.
  ///
  /// Hoje ambos respondem "não avaliado" e nada é gravado a partir disso. A
  /// chamada existe para que a Fase 5 seja preencher a implementação, e não
  /// descobrir onde encaixá-la.
  Future<void> _prepararAnalise(ProcessedImage imagem) async {
    final ScorpionDetectionResult deteccao = await detector.detect(imagem);
    final ClassificationResult classificacao =
        await classifier.classify(imagem);

    assert(
      !deteccao.wasEvaluated && !classificacao.wasEvaluated,
      'Nesta fase nenhum modelo existe. Um resultado avaliado aqui significa '
      'que um placeholder comecou a inventar resposta — ver briefing §12.',
    );
  }

  Future<PipelineOutcome> _abortar(
    String uid,
    String id, {
    bool apagar = true,
  }) async {
    AppLog.event(AppEvent.pipelineCancelled);
    if (apagar) {
      // Sem isto, cancelar deixaria um documento e possivelmente arquivos que
      // ninguém mais referencia.
      try {
        await _uploader.deleteFor(userId: uid, identificationId: id);
      } catch (_) {
        // Limpeza é melhor-esforço: falhar aqui não pode virar erro na tela.
      }
      try {
        await _repository.delete(id);
      } catch (_) {
        // Idem.
      }
    }
    return const PipelineOutcome.cancelled();
  }

  String _requireUid() {
    final String? uid = _auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      throw const AppFailure(
        kind: FailureKind.authentication,
        message: 'Entre na sua conta para salvar identificações.',
        code: 'unauthenticated',
      );
    }
    return uid;
  }

  /// Identificador gerado pelo sistema (§9).
  ///
  /// # Três partes, cada uma resolvendo um problema
  /// `tempo` ordena: documentos criados em sequência ficam vizinhos no índice,
  /// que é o que mantém a consulta de histórico barata.
  ///
  /// `sequencia` desempata dentro do mesmo milissegundo. **Isto não é
  /// paranoia**: a primeira versão usava microssegundos achando que bastava, e
  /// um teste mostrou dois ids idênticos — no Windows `DateTime.now()` tem
  /// resolução de milissegundo, então `microsecondsSinceEpoch` é apenas o
  /// mesmo número multiplicado por mil. Duas identificações rápidas
  /// sobrescreveriam uma à outra.
  ///
  /// `sorteio` cobre o que a sequência não cobre: dois aparelhos diferentes,
  /// ou a mesma pessoa em duas instalações, começam a contagem do zero.
  @visibleForTesting
  static String newId() {
    final String tempo = DateTime.now()
        .toUtc()
        .millisecondsSinceEpoch
        .toRadixString(36)
        .padLeft(8, '0');
    final String sequencia =
        (_contador++ % 1296).toRadixString(36).padLeft(2, '0');
    final String sorteio = List<String>.generate(
      5,
      (_) => _sorte.nextInt(36).toRadixString(36),
    ).join();
    return '$tempo$sequencia$sorteio';
  }

  static int _contador = 0;

  /// `Random.secure` quando a plataforma oferece. Não é questão de sigilo —
  /// um id previsível não dá acesso a nada, porque as regras conferem o dono —
  /// e sim de dispersão: o gerador comum, semeado pelo relógio, pode repetir a
  /// sequência em dois aparelhos que abrem o aplicativo no mesmo instante.
  static final Random _sorte = _criarSorteio();

  static Random _criarSorteio() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }
}
