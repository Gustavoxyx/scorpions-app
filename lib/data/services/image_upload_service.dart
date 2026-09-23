import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../models/captured_image.dart';
import 'failure.dart';
import 'firebase_error_mapper.dart';

/// Envio das fotografias para o Cloud Storage (brief §14, §16).
abstract interface class ImageUploadService {
  /// Envia a imagem e devolve o caminho gravado no documento.
  Future<String?> upload({
    required CapturedImage image,
    required String userId,
    required String identificationId,
  });

  /// Remove os arquivos de uma identificação. Não falha se já não existirem.
  Future<void> deleteFor({
    required String userId,
    required String identificationId,
  });
}

/// Implementação sobre o Firebase Storage.
///
/// # Validação antes de enviar (§16)
/// O arquivo do usuário não é aceito de olhos fechados. Três conferências
/// acontecem aqui: tamanho, extensão e — a que realmente importa — a
/// **assinatura binária** do conteúdo.
///
/// Conferir os bytes iniciais é o que separa validação de teatro: a extensão e
/// o `contentType` são escolhidos por quem envia e podem mentir. Um `.jpg` que
/// na verdade é um executável passa em qualquer checagem de nome; não passa na
/// checagem de assinatura.
///
/// Isto é uma primeira barreira, não a última. A validação definitiva pertence
/// ao servidor e entra na Fase 4, quando uma Function processar a imagem.
class FirebaseImageUploadService implements ImageUploadService {
  FirebaseImageUploadService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  /// Mesmo limite das Storage Rules. Duplicado de propósito: aqui evita gastar
  /// a rede do usuário com um envio que o servidor recusaria de qualquer jeito.
  static const int maxBytes = 8 * 1024 * 1024;

  static const List<String> _allowedExtensions = <String>[
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];

  @override
  Future<String?> upload({
    required CapturedImage image,
    required String userId,
    required String identificationId,
  }) async {
    if (!image.isUploadable) return null;

    final Uint8List bytes = await _readBytes(image);
    _validate(bytes, image);

    final String extension = _extensionOf(image);
    final String path =
        'users/$userId/identifications/$identificationId/original.$extension';

    return FirebaseErrorMapper.guard(
      () async {
        final Reference ref = _storage.ref(path);
        await ref.putData(
          bytes,
          SettableMetadata(
            contentType: _contentTypeFor(extension),
            // Metadado sem dado pessoal (§15): nada de localização, nome do
            // arquivo original ou identificador do aparelho.
            customMetadata: <String, String>{
              'identificationId': identificationId,
            },
          ),
        );
        return path;
      },
      // Upload de imagem em rede móvel merece mais paciência que uma leitura.
      timeout: const Duration(seconds: 90),
    );
  }

  @override
  Future<void> deleteFor({
    required String userId,
    required String identificationId,
  }) async {
    final String prefix = 'users/$userId/identifications/$identificationId';
    // `original` é o único arquivo que esta fase grava; os demais nomes já
    // constam porque a Fase 4 vai gerá-los.
    for (final String name in <String>['original', 'processed', 'thumbnail']) {
      for (final String extension in _allowedExtensions) {
        try {
          await _storage.ref('$prefix/$name.$extension').delete();
        } catch (_) {
          // Arquivo inexistente é o caso normal — não é erro.
        }
      }
    }
  }

  // -- Interno ----------------------------------------------------------------

  Future<Uint8List> _readBytes(CapturedImage image) async {
    if (image.hasBytes) return image.bytes!;
    if (image.hasFile && !kIsWeb) {
      return File(image.path!).readAsBytes();
    }
    throw const AppFailure(
      kind: FailureKind.validation,
      message: 'Não foi possível ler a imagem selecionada.',
      code: 'unreadable-image',
    );
  }

  void _validate(Uint8List bytes, CapturedImage image) {
    if (bytes.isEmpty) {
      throw const AppFailure(
        kind: FailureKind.validation,
        message: 'A imagem está vazia. Tire outra foto.',
        code: 'empty-image',
      );
    }
    if (bytes.length > maxBytes) {
      throw const AppFailure(
        kind: FailureKind.validation,
        message: 'A imagem é grande demais. Tente uma foto menor.',
        code: 'image-too-large',
      );
    }
    if (!_hasImageSignature(bytes)) {
      throw const AppFailure(
        kind: FailureKind.validation,
        message: 'Este arquivo não parece ser uma imagem válida.',
        code: 'invalid-image-signature',
      );
    }
  }

  /// Confere os "números mágicos" no início do arquivo.
  ///
  /// JPEG: `FF D8 FF` · PNG: `89 50 4E 47` · WebP: `RIFF....WEBP`.
  static bool _hasImageSignature(Uint8List bytes) {
    if (bytes.length < 12) return false;

    final bool isJpeg =
        bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
    if (isJpeg) return true;

    final bool isPng = bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    if (isPng) return true;

    final bool isWebp = bytes[0] == 0x52 && // R
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46 && // F
        bytes[3] == 0x46 && // F
        bytes[8] == 0x57 && // W
        bytes[9] == 0x45 && // E
        bytes[10] == 0x42 && // B
        bytes[11] == 0x50; // P
    return isWebp;
  }

  static String _extensionOf(CapturedImage image) {
    final String? path = image.path;
    if (path == null) return 'jpg';
    final int dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'jpg';
    final String extension = path.substring(dot + 1).toLowerCase();
    return _allowedExtensions.contains(extension) ? extension : 'jpg';
  }

  static String _contentTypeFor(String extension) => switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
}

/// Sem upload: usada nos modos simulado e de teste.
class NoopImageUploadService implements ImageUploadService {
  const NoopImageUploadService();

  @override
  Future<String?> upload({
    required CapturedImage image,
    required String userId,
    required String identificationId,
  }) async =>
      null;

  @override
  Future<void> deleteFor({
    required String userId,
    required String identificationId,
  }) async {}
}
