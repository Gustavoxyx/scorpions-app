import 'package:flutter/foundation.dart';

/// Origem da imagem que entra no pipeline de identificação.
enum ImageSource {
  camera,
  gallery,
  simulated,

  /// Já armazenada no Cloud Storage — o aparelho tem apenas a URL.
  remote,
}

/// Imagem submetida à análise.
///
/// Abstrai a origem para que o pipeline funcione igual com câmera real,
/// galeria, modo simulado (desktop e testes) ou imagem já hospedada. A Fase 4
/// acrescenta aqui recorte, redimensionamento e metadados EXIF.
@immutable
class CapturedImage {
  const CapturedImage({
    required this.source,
    required this.capturedAt,
    this.path,
    this.bytes,
    this.url,
  });

  /// Imagem simulada: nenhum arquivo por trás. A UI desenha um placeholder.
  factory CapturedImage.simulated() => CapturedImage(
        source: ImageSource.simulated,
        capturedAt: DateTime.now(),
      );

  /// Imagem que vive no Cloud Storage.
  ///
  /// Usada ao reconstruir uma identificação vinda do banco: o arquivo local
  /// não existe mais (ou nunca existiu neste aparelho).
  factory CapturedImage.remote({
    required String? url,
    required DateTime capturedAt,
  }) {
    return CapturedImage(
      source: url == null ? ImageSource.simulated : ImageSource.remote,
      capturedAt: capturedAt,
      url: url,
    );
  }

  final ImageSource source;
  final DateTime capturedAt;

  /// Caminho no sistema de arquivos do dispositivo. Nulo em modo simulado.
  final String? path;

  /// Bytes em memória (usado quando não há caminho, como na web).
  final Uint8List? bytes;

  /// Endereço no Cloud Storage, quando a imagem já foi enviada.
  final String? url;

  bool get hasFile => path != null && path!.isNotEmpty;
  bool get hasBytes => bytes != null && bytes!.isNotEmpty;
  bool get hasUrl => url != null && url!.isNotEmpty;
  bool get isSimulated => source == ImageSource.simulated;

  /// Se `false`, não há nada para enviar ao Storage — o registro é gravado
  /// sem imagem em vez de falhar.
  bool get isUploadable => hasFile || hasBytes;
}
