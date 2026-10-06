import 'package:flutter/foundation.dart';

import '../core/constants/app_strings.dart';
import '../data/models/capture_instruction.dart';
import '../data/models/captured_image.dart';
import '../data/models/identification.dart';
import '../data/models/processed_image.dart';
import '../data/models/secondary_view.dart';
import '../data/repositories/identification_repository.dart';
import '../data/services/capture_plan_service.dart';
import '../data/services/demo_multi_view_service.dart';
import '../data/services/failure.dart';
import '../data/services/identification_pipeline.dart';
import '../data/services/identification_service.dart';

/// Estados do pipeline de identificação.
///
/// Este é o coração do produto. Os desfechos possíveis existem desde a Fase 1
/// para que a Fase 5 só precise trocar quem produz o [IdentificationResult].
sealed class IdentificationState {
  const IdentificationState();
}

class IdentificationIdle extends IdentificationState {
  const IdentificationIdle();
}

/// Aguardando a escolha de uma imagem (câmera ou galeria).
class IdentificationSelectingImage extends IdentificationState {
  const IdentificationSelectingImage();
}

/// A foto está sendo lida, validada e medida — antes de qualquer envio.
class IdentificationInspecting extends IdentificationState {
  const IdentificationInspecting(this.image);
  final CapturedImage image;
}

/// Trabalho em andamento, com rótulo do que está acontecendo de verdade.
///
/// [message] e [detail] chegam prontos em vez de serem derivados de um índice.
/// O motivo é que duas fontes alimentam esta tela — as etapas reais do
/// pipeline e, no modo de demonstração, os passos do motor simulado — e um
/// índice só faria sentido para uma delas.
class IdentificationAnalyzing extends IdentificationState {
  const IdentificationAnalyzing({
    required this.image,
    required this.message,
    required this.detail,
    required this.stageIndex,
    required this.stageCount,
  });

  final CapturedImage image;
  final String message;
  final String detail;

  /// Posição na sequência, para o contador "etapa 2 de 5".
  ///
  /// Saber quantas faltam transforma uma espera indefinida numa espera com
  /// fim — é a diferença entre o usuário confiar e desistir.
  final int stageIndex;
  final int stageCount;

  /// De 0 a 1.
  double get progress => ((stageIndex + 1) / stageCount).clamp(0.0, 1.0);
}

/// O sistema chegou a uma resposta apresentável.
class IdentificationSuccess extends IdentificationState {
  const IdentificationSuccess(this.result);
  final IdentificationResult result;
}

/// O sistema preferiu não responder. Não é erro — é uma decisão de produto.
class IdentificationRejected extends IdentificationState {
  const IdentificationRejected(this.result);
  final IdentificationResult result;

  RejectionReason get reason => result.rejectionReason!;
}

/// A fotografia foi processada, registrada e enviada — e **não há modelo**
/// para analisá-la (briefing Fase 4, §10 e §31).
///
/// Estado próprio, e não um erro nem um resultado vazio: o trabalho terminou
/// bem, e o que falta é a Fase 5. Chamar isso de falha seria mentir para o
/// usuário sobre o que aconteceu com a foto dele.
class IdentificationAwaitingModel extends IdentificationState {
  const IdentificationAwaitingModel(this.result);
  final IdentificationResult result;
}

/// Falha técnica (câmera, arquivo, rede). Distinta de rejeição.
class IdentificationError extends IdentificationState {
  const IdentificationError(this.message);
  final String message;
}

/// Orquestra captura -> inspeção -> envio -> resultado -> histórico.
///
/// # O que mudou na Fase 4
/// A sequência de verdade mora no [IdentificationPipeline]; este controlador
/// cuida do **estado da interface** em volta dela. A separação importa porque
/// a tela precisa saber coisas que o pipeline não deveria carregar: qual
/// imagem está pendente, o que o usuário já confirmou, e se o aplicativo roda
/// em modo de demonstração.
class IdentificationController extends ChangeNotifier {
  IdentificationController({
    required this._service,
    required this._repository,
    required this._pipeline,
    required this.demonstration,
    this._plan = const HeuristicCapturePlanService(),
    DemoMultiViewService? demoFusion,
  }) : _demoFusion = demoFusion ?? DemoMultiViewService();

  final IdentificationService _service;
  final IdentificationRepository _repository;
  final IdentificationPipeline _pipeline;

  /// Decide qual será a segunda fotografia. Atrás de uma interface para que,
  /// quando houver modelo, a escolha possa passar a depender das espécies
  /// candidatas sem tocar em tela nenhuma.
  final CapturePlanService _plan;

  /// Funde as duas vistas **no modo de demonstração**. Nunca é chamado com
  /// Firebase — ver [demonstration].
  final DemoMultiViewService _demoFusion;

  /// Quando `true`, o motor simulado produz um desfecho apresentável depois do
  /// pipeline, para que o fluxo possa ser demonstrado de ponta a ponta.
  ///
  /// Ligado apenas no modo `mock`. Com Firebase de verdade, inventar uma
  /// espécie gravaria ficção no banco de alguém — o registro fica em
  /// `processing`, que é o que de fato aconteceu.
  final bool demonstration;

  IdentificationState _state = const IdentificationIdle();
  IdentificationState get state => _state;

  CapturedImage? _pendingImage;

  /// Imagem aguardando confirmação do usuário na tela de pré-visualização.
  CapturedImage? get pendingImage => _pendingImage;

  ImagePreparation? _preparation;

  /// Validação, qualidade e formas derivadas da imagem pendente.
  ///
  /// É o que a tela de confirmação usa para avisar sobre foto escura, tremida
  /// ou de resolução curta antes de gastar a rede do usuário (§6).
  ImagePreparation? get preparation => _preparation;

  IdentificationResult? _lastResult;
  IdentificationResult? get lastResult => _lastResult;

  bool _cancelled = false;

  // -- Segunda fotografia (Fase 5) --------------------------------------------

  CapturedImage? _secondImage;

  /// A segunda fotografia, depois de capturada.
  CapturedImage? get secondImage => _secondImage;

  ImagePreparation? _secondPreparation;

  /// Validação e qualidade da segunda fotografia.
  ImagePreparation? get secondPreparation => _secondPreparation;

  bool _capturingSecond = false;

  /// Se a câmera está aberta para a **segunda** foto.
  ///
  /// É o que a tela de captura consulta para saber qual instrução mostrar e
  /// para onde vai a imagem que chegar.
  bool get isCapturingSecond => _capturingSecond;

  ImageCaptureInstruction? _secondInstruction;

  /// O que pedir na segunda fotografia.
  ///
  /// Escolhido a partir do que foi **medido** na primeira — foto no limite da
  /// nitidez pede perfil, não close. Fica fixado em [beginSecondCapture]: a
  /// instrução gravada no registro precisa ser a que a pessoa viu ao
  /// fotografar, e não uma recalculada depois.
  ImageCaptureInstruction get secondInstruction =>
      _secondInstruction ??
      _plan.secondary(primaryQuality: _preparation?.quality);

  /// A instrução em vigor para a câmera, seja qual for a foto da vez.
  ImageCaptureInstruction get currentInstruction =>
      _capturingSecond ? secondInstruction : _plan.primary();

  /// Se existe uma segunda fotografia pronta para seguir junto.
  bool get hasSecondView =>
      _secondImage != null && (_secondPreparation?.canProceed ?? false);

  /// Abre a captura da segunda fotografia.
  void beginSecondCapture() {
    _secondInstruction =
        _plan.secondary(primaryQuality: _preparation?.quality);
    _capturingSecond = true;
    notifyListeners();
  }

  /// Desiste de tirar a segunda — a primeira continua valendo.
  void cancelSecondCapture() {
    if (!_capturingSecond) return;
    _capturingSecond = false;
    notifyListeners();
  }

  /// Descarta a segunda fotografia já tirada, para refazê-la ou seguir sem ela.
  void discardSecondImage() {
    _secondImage = null;
    _secondPreparation = null;
    _capturingSecond = false;
    _set(const IdentificationIdle());
  }

  /// Registra a foto capturada e leva o fluxo à tela de confirmação.
  ///
  /// Para onde ela vai depende do que a câmera estava fazendo: aberta por
  /// [beginSecondCapture], a imagem é a segunda vista; caso contrário é uma
  /// primeira foto nova — e uma primeira foto nova **descarta a segunda**, que
  /// havia sido pedida com base na anterior.
  void stageImage(CapturedImage image) {
    if (_capturingSecond) {
      _secondImage = image;
      _secondPreparation = null;
      _capturingSecond = false;
    } else {
      _pendingImage = image;
      _preparation = null;
      _secondImage = null;
      _secondPreparation = null;
      _secondInstruction = null;
    }
    _set(const IdentificationIdle());
  }

  void discardPendingImage() {
    _pendingImage = null;
    _preparation = null;
    _secondImage = null;
    _secondPreparation = null;
    _secondInstruction = null;
    _capturingSecond = false;
    _set(const IdentificationIdle());
  }

  /// Lê, valida e mede a **segunda** fotografia. Não envia nada.
  ///
  /// Igual a [inspect], sobre a outra foto. Separado para que inspecionar a
  /// segunda nunca toque na preparação da primeira — que já foi aceita, e da
  /// qual a instrução da segunda foi derivada.
  Future<ImagePreparation?> inspectSecond() async {
    final CapturedImage? image = _secondImage;
    if (image == null) return null;

    _cancelled = false;
    _set(IdentificationInspecting(image));
    try {
      final ImagePreparation p = await _pipeline.prepare(image);
      _secondPreparation = p;
      _set(const IdentificationIdle());
      return p;
    } on AppFailure catch (f) {
      _set(IdentificationError(f.message));
      return null;
    } catch (_) {
      _set(const IdentificationError(
        'Não foi possível preparar essa imagem. Tente outra foto.',
      ));
      return null;
    }
  }

  /// Lê, valida e mede a foto pendente. Não envia nada.
  ///
  /// Uma imagem recusada **não** vira erro de tela: devolve a preparação com o
  /// motivo, e quem decide o que mostrar é a interface.
  Future<ImagePreparation?> inspect(CapturedImage image) async {
    _cancelled = false;
    _pendingImage = image;
    _set(IdentificationInspecting(image));
    try {
      final ImagePreparation p = await _pipeline.prepare(image);
      _preparation = p;
      _set(const IdentificationIdle());
      return p;
    } on AppFailure catch (f) {
      _set(IdentificationError(f.message));
      return null;
    } catch (_) {
      _set(const IdentificationError(
        'Não foi possível preparar essa imagem. Tente outra foto.',
      ));
      return null;
    }
  }

  /// Envia a fotografia e registra a identificação.
  ///
  /// Exige uma [inspect] bem-sucedida antes — a tela de confirmação já a fez.
  Future<void> submit(CapturedImage image) async {
    final ImagePreparation? p = _preparation;
    if (p == null || !p.canProceed) {
      _set(const IdentificationError(
        'Essa foto não pode ser analisada. Tire outra.',
      ));
      return;
    }

    _cancelled = false;
    _pendingImage = image;
    _etapa(image, PipelineStage.reading);

    try {
      // A segunda fotografia segue junto só se existir **e** tiver passado na
      // inspeção. Uma segunda foto recusada não bloqueia a análise: a primeira
      // já foi aceita, e uma vista ruim não invalida a identificação se a
      // outra tiver informação suficiente (§5).
      final CapturedImage? segundaImagem = _secondImage;
      final ImagePreparation? segundaPrep = _secondPreparation;
      final SecondaryCapture? segunda =
          segundaImagem != null && segundaPrep != null && segundaPrep.canProceed
              ? SecondaryCapture(
                  image: segundaImagem,
                  preparation: segundaPrep,
                  instruction: secondInstruction,
                )
              : null;

      final PipelineOutcome saida = await _pipeline.submit(
        image: image,
        preparation: p,
        secondary: segunda,
        onStage: (PipelineStage s) {
          if (_cancelled) return;
          _etapa(image, s);
        },
      );

      if (_cancelled || saida.cancelled) {
        _set(const IdentificationIdle());
        return;
      }

      final IdentificationResult registro = saida.result!;
      _lastResult = registro;

      if (!demonstration) {
        _set(IdentificationAwaitingModel(registro));
        return;
      }

      await _demonstrar(image, registro);
    } on AppFailure catch (f) {
      if (_cancelled) return;
      _set(IdentificationError(f.message));
    } catch (_) {
      if (_cancelled) return;
      _set(const IdentificationError(
        'A análise não pôde ser concluída. Tente novamente.',
      ));
    }
  }

  /// Interrompe o que estiver em andamento sem gravar nada.
  void cancel() {
    _cancelled = true;
    _pipeline.cancel();
    _set(const IdentificationIdle());
  }

  /// Recoloca um resultado do histórico como resultado corrente, para que a
  /// tela de resultado possa ser reaproveitada.
  void showExisting(IdentificationResult result) {
    _lastResult = result;
    _set(result.isRejected
        ? IdentificationRejected(result)
        : IdentificationSuccess(result));
  }

  void reset() {
    _pendingImage = null;
    _preparation = null;
    _secondImage = null;
    _secondPreparation = null;
    _secondInstruction = null;
    _capturingSecond = false;
    _lastResult = null;
    _set(const IdentificationIdle());
  }

  // -- Interno ----------------------------------------------------------------

  /// Desfecho simulado, exibido só no modo de demonstração.
  ///
  /// O selo de dado simulado acompanha cada tela que o exibe. O registro já
  /// gravado pelo pipeline é atualizado com as hipóteses, mantendo id,
  /// caminhos de imagem e medidas de qualidade — assim o histórico continua
  /// apontando para os mesmos arquivos.
  Future<void> _demonstrar(
    CapturedImage image,
    IdentificationResult registro,
  ) async {
    final int passos = AppStrings.analyzingSteps.length;
    final IdentificationResult simulado = await _service.identify(
      image,
      stageCount: passos,
      onStage: (int i) {
        if (_cancelled) return;
        final int k = i.clamp(0, passos - 1);
        _set(IdentificationAnalyzing(
          image: image,
          message: AppStrings.analyzingSteps[k],
          detail: AppStrings.analyzingDetails[k],
          stageIndex: k,
          stageCount: passos,
        ));
      },
    );

    if (_cancelled) return;

    // Com duas fotografias, o desfecho deixa de ser o da primeira vista e
    // passa a ser o da FUSÃO. O que cada foto "disse" é simulado; a fusão e a
    // decisão são as de produção — ver [DemoMultiViewService].
    //
    // Uma primeira vista rejeitada pelo motor simulado segue rejeitada: sem
    // hipótese nenhuma não há o que fundir.
    IdentificationResult desfecho = simulado;
    final SecondaryView? segundaVista = registro.secondaryView;
    if (segundaVista != null && !simulado.isRejected) {
      final DemoFusionOutcome fusao = _demoFusion.combine(
        first: simulado.predictions,
        secondType: segundaVista.captureType,
        firstQuality: _preparation?.quality?.quality,
        secondQuality: _secondPreparation?.quality?.quality,
      );

      desfecho = (fusao.showsSpecies && fusao.predictions.isNotEmpty
              ? IdentificationResult.identified(
                  id: registro.id,
                  image: image,
                  isMock: true,
                  predictions: fusao.predictions,
                )
              // As duas fotos discordaram, ou a evidência não bastou. Mostrar
              // uma das duas espécies em silêncio seria exatamente o que a
              // segunda foto existe para impedir.
              : IdentificationResult.rejected(
                  id: registro.id,
                  image: image,
                  isMock: true,
                  reason: RejectionReason.ambiguous,
                ))
          .copyWith(multiView: fusao.summary);
    }

    final IdentificationResult combinado = desfecho.copyWith(
      // O MESMO id do registro que o pipeline criou.
      //
      // Isto era um defeito. O motor simulado devolve um resultado com id
      // próprio (`mock-…`), e gravá-lo assim deixava DOIS registros no
      // histórico a cada identificação: o desfecho, e o registro original
      // preso em "processando" para sempre. O comentário acima deste método
      // sempre disse "mantendo id" — o código é que não mantinha.
      id: registro.id,
      userId: registro.userId,
      imageUrl: registro.imageUrl,
      thumbnailUrl: registro.thumbnailUrl,
      imageQuality: registro.imageQuality,
      secondaryView: segundaVista,
    );

    _lastResult = combinado;
    await _repository.save(combinado);

    _set(combinado.isRejected
        ? IdentificationRejected(combinado)
        : IdentificationSuccess(combinado));
  }

  void _etapa(CapturedImage image, PipelineStage stage) {
    _set(IdentificationAnalyzing(
      image: image,
      message: stage.label,
      detail: stage.detail,
      stageIndex: stage.index,
      stageCount: PipelineStage.values.length,
    ));
  }

  void _set(IdentificationState next) {
    _state = next;
    notifyListeners();
  }
}
