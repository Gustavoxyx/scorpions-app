import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/captured_image.dart';

/// Apaga do aparelho a fotografia que já não é mais necessária.
///
/// A câmera grava cada captura num arquivo no cache do aplicativo, e esse
/// arquivo ficava lá depois do envio — uma cópia em claro de uma foto que as
/// regras do servidor tratam como dado sensível. O sistema operacional limpa o
/// cache quando precisa de espaço, e só então.
abstract interface class CaptureCleanup {
  /// Descarta o arquivo por trás de [image], se houver um que seja nosso.
  ///
  /// Nunca lança: falhar em apagar um temporário não pode virar erro de tela.
  Future<void> discard(CapturedImage image);
}

/// Apaga apenas o que a **câmera do próprio aplicativo** criou.
///
/// # Por que só a câmera
/// Uma imagem escolhida na galeria pode ser o arquivo original do usuário, e
/// não uma cópia: é o que acontece no desktop, onde o seletor devolve o caminho
/// de verdade. Apagar isso seria destruir uma fotografia que não nos pertence.
/// Como não há forma confiável de distinguir os dois casos pelo caminho, a
/// regra é pela origem: só é apagado o que este aplicativo fotografou.
///
/// As cópias que o seletor de galeria deixa no cache continuam sob a limpeza
/// do sistema.
class FileCaptureCleanup implements CaptureCleanup {
  const FileCaptureCleanup();

  @override
  Future<void> discard(CapturedImage image) async {
    if (kIsWeb) return;
    if (image.source != ImageSource.camera || !image.hasFile) return;

    try {
      final File arquivo = File(image.path!);
      if (await arquivo.exists()) await arquivo.delete();
    } catch (_) {
      // Arquivo já removido pelo sistema, ou em uso: o cache continua sendo
      // limpo por ele.
    }
  }
}

/// Não apaga nada.
///
/// Usado no modo de demonstração, onde o histórico vive na memória e aponta
/// para o arquivo local: apagar o arquivo apagaria a foto do histórico.
class NoopCaptureCleanup implements CaptureCleanup {
  const NoopCaptureCleanup();

  @override
  Future<void> discard(CapturedImage image) async {}
}
