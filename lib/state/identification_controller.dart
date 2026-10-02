import 'package:flutter/foundation.dart';

import '../core/constants/app_strings.dart';
import '../data/models/captured_image.dart';
import '../data/models/identification.dart';
import '../data/models/processed_image.dart';
import '../data/repositories/identification_repository.dart';
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
  });

  final IdentificationService _service;
  final IdentificationRepository _repository;
  final IdentificationPipeline _pipeline;

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

  /// Registra a foto capturada e leva o fluxo à tela de confirmação.
  void stageImage(CapturedImage image) {
    _pendingImage = image;
    _preparation = null;
    _set(const IdentificationIdle());
  }

  void discardPendingImage() {
    _pendingImage = null;
    _preparation = null;
    _set(const IdentificationIdle());
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
      final PipelineOutcome saida = await _pipeline.submit(
        image: image,
        preparation: p,
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

    final IdentificationResult combinado = simulado.copyWith(
      userId: registro.userId,
      imageUrl: registro.imageUrl,
      thumbnailUrl: registro.thumbnailUrl,
      imageQuality: registro.imageQuality,
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
