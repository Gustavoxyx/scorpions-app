import 'dart:io' show File;

import 'package:flutter/foundation.dart';

import '../models/captured_image.dart';
import 'failure.dart';

/// Lê os bytes de uma [CapturedImage], venha ela de onde vier.
///
/// Existe como função solta porque dois lugares precisam da mesma coisa — o
/// pipeline e o envio ao Storage — e a primeira versão deste projeto tinha uma
/// cópia em cada um.
///
/// Na web não há sistema de arquivos acessível: a imagem chega como bytes em
/// memória. No aparelho chega como caminho. A diferença fica aqui e em nenhum
/// outro lugar.
Future<Uint8List> readImageBytes(CapturedImage image) async {
  if (image.hasBytes) return image.bytes!;
  if (image.hasFile && !kIsWeb) {
    try {
      return await File(image.path!).readAsBytes();
    } catch (_) {
      throw const AppFailure(
        kind: FailureKind.validation,
        message: 'Não foi possível abrir essa imagem. Tente escolher outra.',
        code: 'unreadable-image',
      );
    }
  }
  throw const AppFailure(
    kind: FailureKind.validation,
    message: 'Não foi possível ler a imagem selecionada.',
    code: 'unreadable-image',
  );
}
