import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/observability/app_log.dart';
import '../models/capture_instruction.dart';
import '../models/captured_image.dart';
import '../models/classification.dart';
import '../models/detection.dart';
import '../models/identification.dart';
import '../models/processed_image.dart';
import '../models/secondary_view.dart';
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

/// A segunda fotografia, pronta para envio.
///
/// Junta as três coisas que o pipeline precisa dela e que nascem em momentos
/// diferentes: a captura, o que a inspeção mediu, e o que havia sido **pedido**.
/// A instrução vai junto para ficar registrada — sem ela não há como perguntar,
/// depois, se o usuário fotografou a cauda quando pedimos a cauda.
@immutable
class SecondaryCapture {
  const SecondaryCapture({
    required this.image,
    required this.preparation,
    required this.instruction,
  });

  final CapturedImage image;
  final ImagePreparation preparation;
  final ImageCaptureInstruction instruction;
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
    this.requireVerifiedEmail = false,
    this.detector = const MockScorpionDetectionService(),
    this.classifier = const MockSpeciesClassificationService(),
  });

  final AuthRepository _auth;
  final IdentificationRepository _repository;
  final ImageProcessingService _processing;
  final ImageUploadService _uploader;
  final ConnectivityService _connectivity;

  /// Se o envio exige e-mail confirmado.
  ///
  /// Ligado quando há infraestrutura de verdade por trás: as Security Rules
  /// recusam a criação de conteúdo por conta sem confirmação, e conferir aqui
  /// troca um "permissão negada" sem explicação por uma frase que diz o que
  /// fazer. No modo simulado fica desligado — ali não há e-mail para confirmar.
  final bool requireVerifiedEmail;

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
  ///
  /// [secondary] é a segunda fotografia, opcional. Opcional de verdade: o animal
  /// pode ter fugido, a pessoa pode estar em situação de risco, o aparelho pode
  /// não ter focado. Uma identificação de uma foto só continua válida.
  Future<PipelineOutcome> submit({
    required CapturedImage image,
    required ImagePreparation preparation,
    SecondaryCapture? secondary,
    void Function(PipelineStage stage)? onStage,
  }) async {
    assert(preparation.canProceed, 'submit exige uma preparação utilizável');
    assert(
      secondary == null || secondary.preparation.canProceed,
      'a segunda fotografia também precisa de uma preparação utilizável',
    );

    final ProcessedImage? processada = preparation.image;
    final String uid = _requireUid();
    await _requireVerifiedEmail();
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

    final ProcessedImage? segundaProcessada = secondary?.preparation.image;

    // A segunda vista nasce junto do registro, já com o que se sabe dela antes
    // do envio: o que foi pedido e o que o aparelho mediu. Os caminhos entram
    // depois, como os da primeira.
    SecondaryView? segunda = secondary == null
        ? null
        : SecondaryView(
            captureType: secondary.instruction.captureType,
            instructionId: secondary.instruction.id,
            image: secondary.image,
            imageQuality: secondary.preparation.quality?.toMap(),
          );

    IdentificationResult registro = IdentificationResult.processing(
      id: id,
      image: image,
      userId: uid,
      imageQuality: preparation.quality?.toMap(),
      secondaryView: segunda,
    );
    await _repository.save(registro);
    AppLog.event(AppEvent.identificationCreated, <String, Object?>{
      'quality': preparation.quality?.quality.name ?? 'simulada',
      'views': registro.viewCount,
    });

    if (processada != null || segundaProcessada != null) {
      onStage?.call(PipelineStage.uploading);
      if (_cancelled) return _abortar(uid, id);

      AppLog.event(AppEvent.uploadStarted, <String, Object?>{
        'kb': (((processada?.totalBytes ?? 0) +
                    (segundaProcessada?.totalBytes ?? 0)) /
                1024)
            .round(),
        'views': registro.viewCount,
      });

      // As duas vistas sobem AO MESMO TEMPO.
      //
      // Não dependem uma da outra, e esperar a primeira terminar para começar a
      // segunda dobraria o tempo que o usuário passa olhando para a tela de
      // envio. O briefing de otimização (§27) pede exatamente isto.
      //
      // Cada uma tem a própria tolerância a falha — ver [_enviarVista]. Uma
      // exceção na segunda não pode derrubar a primeira, nem o contrário:
      // `Future.wait` sobre futuros que nunca lançam é o que garante isso.
      final List<_ResultadoDeEnvio> envios =
          await Future.wait<_ResultadoDeEnvio>(<Future<_ResultadoDeEnvio>>[
        _enviarVista(processada, uid: uid, id: id, viewIndex: 1),
        _enviarVista(segundaProcessada, uid: uid, id: id, viewIndex: 2),
      ]);
      final _ResultadoDeEnvio primeira = envios[0];
      final _ResultadoDeEnvio segundaEnviada = envios[1];

      if (_cancelled) return _abortar(uid, id);

      // O código de erro do registro fala da primeira foto, que é a que
      // sustenta a identificação. Se só a segunda falhou, o registro continua
      // utilizável com uma vista — e isso fica marcado com um código próprio,
      // para não ser confundido com "a identificação ficou sem imagem".
      final String? falha = primeira.falha ??
          (segundaEnviada.falha == null ? null : 'second-view-upload-failed');

      segunda = segunda?.copyWith(
        imageUrl: segundaEnviada.caminhos?.forAnalysis,
        thumbnailUrl: segundaEnviada.caminhos?.thumbnail,
      );

      // A referência gravada aponta para a versão de análise, com queda para
      // o original: é ela que um modelo vai consumir.
      registro = registro.copyWith(
        imageUrl: primeira.caminhos?.forAnalysis,
        thumbnailUrl: primeira.caminhos?.thumbnail,
        errorCode: falha,
        secondaryView: segunda,
      );

      // Se nem a marcação conseguir ser gravada, o registro continua de pé
      // como foi criado. Insistir aqui só transformaria um problema de rede
      // em erro de tela para um trabalho que já terminou.
      try {
        await _repository.attachUploadResult(
          id,
          imageUrl: primeira.caminhos?.forAnalysis,
          thumbnailUrl: primeira.caminhos?.thumbnail,
          errorCode: falha,
          secondaryView: segunda,
        );
      } catch (_) {}
    }

    onStage?.call(PipelineStage.awaitingAnalysis);
    // Em paralelo, pelo mesmo motivo do envio: analisar a foto de cima não
    // precisa de nada que venha do close da cauda.
    await Future.wait<void>(<Future<void>>[
      if (processada != null) _prepararAnalise(processada),
      if (segundaProcessada != null) _prepararAnalise(segundaProcessada),
    ]);

    return PipelineOutcome.completed(registro);
  }

  /// Envia uma vista e **nunca lança**.
  ///
  /// O envio pode falhar sem que nada esteja errado com a foto.
  ///
  /// O caso concreto deste projeto: o Cloud Storage exige plano Blaze, que
  /// ainda não foi autorizado, então `uploadAll` lança a cada tentativa. Sem
  /// este `catch`, a exceção subiria e o usuário veria um erro — mas o
  /// documento já teria sido gravado e ficaria preso em `processing` para
  /// sempre, invisível e órfão.
  ///
  /// Esta tolerância existia na Fase 3, dentro do repositório. Ao mover o envio
  /// para o pipeline ela ficou para trás uma vez; ao passar para duas vistas
  /// ela veio para cá, para que as duas a tenham igual e uma falha numa não
  /// alcance a outra.
  ///
  /// Perder a foto é ruim. Perder a foto **e** o registro é pior: a
  /// identificação sobrevive marcada, e a tela tem como explicar por quê.
  Future<_ResultadoDeEnvio> _enviarVista(
    ProcessedImage? imagem, {
    required String uid,
    required String id,
    required int viewIndex,
  }) async {
    // Vista ausente, ou simulada: não há o que enviar, e isso não é falha.
    if (imagem == null) return const _ResultadoDeEnvio();

    try {
      final UploadedImagePaths caminhos = await _uploader.uploadAll(
        image: imagem,
        userId: uid,
        identificationId: id,
        viewIndex: viewIndex,
      );
      AppLog.event(AppEvent.uploadCompleted, <String, Object?>{
        'files': caminhos.uploadedCount,
        'view': viewIndex,
      });
      return _ResultadoDeEnvio(caminhos: caminhos);
    } on AppFailure catch (e) {
      final String codigo = e.code ?? 'upload-failed';
      AppLog.event(AppEvent.uploadFailed, <String, Object?>{
        'code': codigo,
        'view': viewIndex,
      });
      return _ResultadoDeEnvio(falha: codigo);
    } catch (_) {
      AppLog.event(AppEvent.uploadFailed, <String, Object?>{
        'code': 'upload-failed',
        'view': viewIndex,
      });
      return const _ResultadoDeEnvio(falha: 'upload-failed');
    }
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

  /// Interrompe se o envio exige e-mail confirmado e ele não foi.
  ///
  /// A confirmação acontece num navegador, fora do aplicativo, e o usuário em
  /// memória não fica sabendo. Por isso há uma recarga antes de recusar:
  /// barrar quem acabou de confirmar seria o pior momento para errar.
  Future<void> _requireVerifiedEmail() async {
    if (!requireVerifiedEmail) return;
    if (_auth.currentUser?.emailVerified ?? false) return;

    bool confirmado = false;
    try {
      confirmado = (await _auth.reload())?.emailVerified ?? false;
    } catch (_) {
      // Sem rede para recarregar, vale o que está em memória: não confirmado.
    }
    if (confirmado) return;

    throw const AppFailure(
      kind: FailureKind.permission,
      message: 'Confirme seu e-mail para enviar fotografias. '
          'O link está em Perfil › Configurações › Meus dados.',
      code: 'email-not-verified',
    );
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

/// O que aconteceu com o envio de uma vista.
///
/// Os dois campos nulos significam "não havia o que enviar" — vista ausente ou
/// simulada. É diferente de falha, e por isso não vira código de erro.
@immutable
class _ResultadoDeEnvio {
  const _ResultadoDeEnvio({this.caminhos, this.falha});

  final UploadedImagePaths? caminhos;
  final String? falha;
}
