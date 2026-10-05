import 'package:image_picker/image_picker.dart' as picker;

import '../models/captured_image.dart';

/// Seleção de uma imagem já existente no aparelho.
///
/// Fica atrás de uma interface para que a tela de câmera não conheça o plugin.
abstract interface class GalleryService {
  /// Retorna `null` quando o usuário cancela a seleção.
  Future<CapturedImage?> pick();
}

class ImagePickerGalleryService implements GalleryService {
  ImagePickerGalleryService();

  final picker.ImagePicker _picker = picker.ImagePicker();

  @override
  Future<CapturedImage?> pick() async {
    // O arquivo vem intacto, de propósito.
    //
    // Até a Fase 4 este método passava `maxWidth`, `maxHeight` e
    // `imageQuality` ao plugin, e isso virou um problema quando o pipeline
    // nasceu: o plugin **recomprime e reescreve** o arquivo para atender a
    // esses parâmetros. O resultado era um original que já não era original.
    //
    // Três efeitos, todos medidos no código:
    //
    // 1. Dupla compressão. O plugin gravava a 88 e o pipeline regravava o
    //    "original" a 95 (`ImageLimits.originalQuality`) — recomprimir o que
    //    já perdeu informação não devolve nada, só degrada o insumo do
    //    modelo da Fase 5.
    // 2. Orientação perdida. A reescrita descarta o EXIF, então
    //    `MetadataStripper.readJpegOrientation` nunca via a etiqueta e uma
    //    foto deitada podia chegar deitada à análise.
    // 3. Validação cega. `ImageLimits.maxDimension` nunca era exercido,
    //    porque o plugin já havia encolhido a imagem antes da conferência.
    //
    // Hoje quem decide tamanho, qualidade e orientação é o pipeline, em um
    // lugar só. Uma foto grande demais é **recusada com mensagem**, que é
    // honesto, em vez de encolhida em silêncio.
    final picker.XFile? file = await _picker.pickImage(
      source: picker.ImageSource.gallery,
    );
    if (file == null) return null;
    return CapturedImage(
      source: ImageSource.gallery,
      capturedAt: DateTime.now(),
      path: file.path,
    );
  }
}
