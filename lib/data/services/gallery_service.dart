import 'package:image_picker/image_picker.dart' as picker;

import '../models/captured_image.dart';

/// Seleção de uma imagem já existente no aparelho.
///
/// Fica atrás de uma interface para que a tela de câmera não conheça o plugin
/// e para que ambientes sem suporte (desktop, testes) usem a variante simulada
/// sem quebrar o fluxo.
abstract interface class GalleryService {
  /// Retorna `null` quando o usuário cancela a seleção.
  Future<CapturedImage?> pick();
}

class ImagePickerGalleryService implements GalleryService {
  ImagePickerGalleryService();

  final picker.ImagePicker _picker = picker.ImagePicker();

  @override
  Future<CapturedImage?> pick() async {
    // Reduzimos a imagem já na seleção: o modelo da Fase 5 não precisa de
    // resolução total, e arquivos menores poupam memória em aparelhos modestos.
    final picker.XFile? file = await _picker.pickImage(
      source: picker.ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 88,
    );
    if (file == null) return null;
    return CapturedImage(
      source: ImageSource.gallery,
      capturedAt: DateTime.now(),
      path: file.path,
    );
  }
}

/// Usada quando a plataforma não oferece seleção de arquivos (ou em testes).
class SimulatedGalleryService implements GalleryService {
  const SimulatedGalleryService();

  @override
  Future<CapturedImage?> pick() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return CapturedImage.simulated();
  }
}
