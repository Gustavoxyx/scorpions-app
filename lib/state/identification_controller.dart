import 'package:flutter/foundation.dart';

import '../core/constants/app_strings.dart';
import '../data/models/captured_image.dart';
import '../data/models/identification.dart';
import '../data/repositories/identification_repository.dart';
import '../data/services/identification_service.dart';

/// Estados do pipeline de identificação.
///
/// Este é o coração do produto. Os quatro desfechos possíveis (sucesso,
/// confiança baixa, rejeição e erro) existem desde a Fase 1 para que a Fase 5
/// só precise trocar quem produz o [IdentificationResult].
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

class IdentificationAnalyzing extends IdentificationState {
  const IdentificationAnalyzing({
    required this.image,
    required this.stageIndex,
    required this.stageCount,
  });

  final CapturedImage image;
  final int stageIndex;
  final int stageCount;

  int get _safeIndex =>
      stageIndex.clamp(0, AppStrings.analyzingSteps.length - 1);

  /// Título da etapa corrente.
  String get message => AppStrings.analyzingSteps[_safeIndex];

  /// Explicação técnica do que está acontecendo nesta etapa.
  String get detail => AppStrings.analyzingDetails[_safeIndex];

  /// Progresso aproximado. Quando o modelo real informar progresso verdadeiro,
  /// só esta linha muda.
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

/// Falha técnica (câmera, arquivo, rede). Distinta de rejeição.
class IdentificationError extends IdentificationState {
  const IdentificationError(this.message);
  final String message;
}

/// Orquestra captura -> análise -> resultado -> histórico.
class IdentificationController extends ChangeNotifier {
  IdentificationController({
    required this._service,
    required this._repository,
  });

  final IdentificationService _service;
  final IdentificationRepository _repository;

  IdentificationState _state = const IdentificationIdle();
  IdentificationState get state => _state;

  CapturedImage? _pendingImage;

  /// Imagem aguardando confirmação do usuário na tela de pré-visualização.
  CapturedImage? get pendingImage => _pendingImage;

  /// Último resultado, mantido para que as telas de resultado sobrevivam a
  /// reconstruções do roteador.
  IdentificationResult? _lastResult;
  IdentificationResult? get lastResult => _lastResult;

  bool _cancelled = false;

  /// Registra a foto capturada e leva o fluxo à tela de confirmação.
  void stageImage(CapturedImage image) {
    _pendingImage = image;
    _set(const IdentificationIdle());
  }

  void discardPendingImage() {
    _pendingImage = null;
    _set(const IdentificationIdle());
  }

  /// Executa a análise da imagem já confirmada.
  Future<void> analyze(CapturedImage image) async {
    _cancelled = false;
    _pendingImage = image;
    // A contagem vem da lista de etapas: acrescentar uma etapa ao pipeline é
    // editar `AppStrings.analyzingSteps`, não caçar um número por aqui.
    final int stages = AppStrings.analyzingSteps.length;
    _set(IdentificationAnalyzing(
      image: image,
      stageIndex: 0,
      stageCount: stages,
    ));

    try {
      final IdentificationResult result = await _service.identify(
        image,
        stageCount: stages,
        onStage: (int index) {
          if (_cancelled) return;
          _set(IdentificationAnalyzing(
            image: image,
            stageIndex: index,
            stageCount: stages,
          ));
        },
      );

      if (_cancelled) return;

      _lastResult = result;
      await _repository.save(result);

      _set(result.isRejected
          ? IdentificationRejected(result)
          : IdentificationSuccess(result));
    } catch (_) {
      if (_cancelled) return;
      _set(const IdentificationError(
        'A análise não pôde ser concluída. Tente novamente.',
      ));
    }
  }

  /// Interrompe a análise em andamento sem gravar nada.
  void cancel() {
    _cancelled = true;
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
    _lastResult = null;
    _set(const IdentificationIdle());
  }

  void _set(IdentificationState next) {
    _state = next;
    notifyListeners();
  }
}
