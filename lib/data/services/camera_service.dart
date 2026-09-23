import 'package:camera/camera.dart';

import '../models/captured_image.dart';

/// Situação da câmera do dispositivo.
///
/// Modelado como estado explícito desde a Fase 1 porque "permissão negada" e
/// "sem câmera" são caminhos de produto reais, não exceções a esconder.
enum CameraAvailability {
  /// Há ao menos uma câmera utilizável.
  available,

  /// O usuário negou o acesso.
  permissionDenied,

  /// Nenhuma câmera encontrada ou plataforma sem suporte.
  unsupported,

  /// Falha inesperada ao consultar o hardware.
  failed,
}

/// Resultado da sondagem inicial do hardware.
class CameraProbe {
  const CameraProbe(this.availability, {this.cameras = const <CameraDescription>[]});

  final CameraAvailability availability;
  final List<CameraDescription> cameras;

  bool get isUsable =>
      availability == CameraAvailability.available && cameras.isNotEmpty;
}

/// Acesso à câmera do aparelho.
///
/// A interface existe para que a tela de captura não dependa do plugin: em
/// plataformas sem suporte usamos [SimulatedCameraService] e o fluxo completo
/// (captura -> confirmação -> análise) continua navegável.
abstract interface class CameraService {
  /// Consulta o hardware sem abrir a câmera nem pedir permissão além do
  /// necessário.
  Future<CameraProbe> probe();

  /// Captura uma foto usando um controlador já inicializado.
  Future<CapturedImage> capture(CameraController controller);
}

class DeviceCameraService implements CameraService {
  const DeviceCameraService();

  @override
  Future<CameraProbe> probe() async {
    try {
      final List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty) {
        return const CameraProbe(CameraAvailability.unsupported);
      }
      return CameraProbe(CameraAvailability.available, cameras: cameras);
    } on CameraException catch (e) {
      return CameraProbe(_mapException(e));
    } catch (_) {
      // Plataformas sem implementação do plugin lançam MissingPluginException.
      return const CameraProbe(CameraAvailability.unsupported);
    }
  }

  @override
  Future<CapturedImage> capture(CameraController controller) async {
    final XFile file = await controller.takePicture();
    return CapturedImage(
      source: ImageSource.camera,
      capturedAt: DateTime.now(),
      path: file.path,
    );
  }

  static CameraAvailability _mapException(CameraException e) {
    return switch (e.code) {
      'CameraAccessDenied' ||
      'CameraAccessDeniedWithoutPrompt' ||
      'CameraAccessRestricted' =>
        CameraAvailability.permissionDenied,
      'cameraNotFound' => CameraAvailability.unsupported,
      _ => CameraAvailability.failed,
    };
  }
}

/// Câmera simulada. Mantém o fluxo utilizável em desktop, em emuladores sem
/// câmera e em testes de widget.
class SimulatedCameraService implements CameraService {
  const SimulatedCameraService();

  @override
  Future<CameraProbe> probe() async =>
      const CameraProbe(CameraAvailability.unsupported);

  @override
  Future<CapturedImage> capture(CameraController controller) async =>
      CapturedImage.simulated();
}
