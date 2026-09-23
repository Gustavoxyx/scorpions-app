import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import '../../data/models/captured_image.dart';
import '../../data/services/camera_service.dart';

/// Situação da sessão de câmera, do ponto de vista da interface.
enum CameraSessionStatus {
  /// Sondando o hardware e inicializando o controlador.
  initializing,

  /// Pronta para capturar.
  ready,

  /// Captura em andamento.
  capturing,

  /// O usuário negou o acesso.
  permissionDenied,

  /// Sem câmera utilizável nesta plataforma (desktop, emulador sem câmera).
  /// O fluxo continua pela galeria ou pelo modo simulado.
  unavailable,

  /// Falha inesperada.
  error,
}

/// Ciclo de vida da câmera.
///
/// Isola o plugin `camera` do widget: a tela observa apenas [status] e
/// [controller]. Isso mantém a página de captura legível e permite testá-la
/// com uma sessão falsa.
class CameraSession extends ChangeNotifier with WidgetsBindingObserver {
  CameraSession(this._service);

  final CameraService _service;

  CameraController? _controller;
  CameraController? get controller => _controller;

  CameraSessionStatus _status = CameraSessionStatus.initializing;
  CameraSessionStatus get status => _status;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<CameraDescription> _cameras = <CameraDescription>[];
  bool get canSwitchCamera => _cameras.length > 1;

  int _cameraIndex = 0;
  bool _disposed = false;

  bool get isReady =>
      _status == CameraSessionStatus.ready &&
      (_controller?.value.isInitialized ?? false);

  Future<void> start() async {
    _set(CameraSessionStatus.initializing);

    final CameraProbe probe = await _service.probe();
    if (_disposed) return;

    if (!probe.isUsable) {
      _set(switch (probe.availability) {
        CameraAvailability.permissionDenied =>
          CameraSessionStatus.permissionDenied,
        CameraAvailability.failed => CameraSessionStatus.error,
        _ => CameraSessionStatus.unavailable,
      });
      return;
    }

    _cameras = probe.cameras;
    // Preferimos a traseira: é a que enquadra o animal no chão.
    _cameraIndex = _cameras.indexWhere(
      (CameraDescription c) => c.lensDirection == CameraLensDirection.back,
    );
    if (_cameraIndex < 0) _cameraIndex = 0;

    await _bind(_cameras[_cameraIndex]);
  }

  Future<void> _bind(CameraDescription description) async {
    await _controller?.dispose();
    if (_disposed) return;

    final CameraController controller = CameraController(
      description,
      // Média resolução: suficiente para o classificador da Fase 5 e muito
      // mais leve em aparelhos modestos.
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = controller;

    try {
      await controller.initialize();
      if (_disposed) return;
      _set(CameraSessionStatus.ready);
    } on CameraException catch (e) {
      _errorMessage = e.description;
      _set(
        e.code == 'CameraAccessDenied'
            ? CameraSessionStatus.permissionDenied
            : CameraSessionStatus.error,
      );
    }
  }

  Future<void> switchCamera() async {
    if (!canSwitchCamera || _status != CameraSessionStatus.ready) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    _set(CameraSessionStatus.initializing);
    await _bind(_cameras[_cameraIndex]);
  }

  /// Captura a foto. Retorna `null` se a câmera não estiver pronta.
  Future<CapturedImage?> capture() async {
    final CameraController? controller = _controller;
    if (controller == null || !isReady) return null;

    _set(CameraSessionStatus.capturing);
    try {
      final CapturedImage image = await _service.capture(controller);
      if (!_disposed) _set(CameraSessionStatus.ready);
      return image;
    } on CameraException catch (e) {
      _errorMessage = e.description;
      _set(CameraSessionStatus.error);
      return null;
    }
  }

  /// Libera a câmera quando o app vai para segundo plano e a retoma na volta.
  /// Sem isso, o Android devolve uma tela preta ao reabrir.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _bind(controller.description);
    }
  }

  void _set(CameraSessionStatus next) {
    if (_disposed) return;
    _status = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _controller?.dispose();
    super.dispose();
  }
}
