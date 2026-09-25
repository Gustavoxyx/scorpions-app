import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../models/captured_image.dart';
import '../models/image_validation.dart';
import 'failure.dart';
import 'firebase_error_mapper.dart';
import 'image_validator.dart';

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

  @override
  Future<String?> upload({
    required CapturedImage image,
    required String userId,
    required String identificationId,
  }) async {
    if (!image.isUploadable) return null;

    final Uint8List bytes = await _readBytes(image);
    final ImageFormat formato = _validate(bytes);
    final String path = 'users/$userId/identifications/$identificationId/'
        'original.${formato.extension}';

    return FirebaseErrorMapper.guard(
      () async {
        final Reference ref = _storage.ref(path);
        await ref.putData(
          bytes,
          SettableMetadata(
            contentType: formato.mimeType,
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
      for (final ImageFormat f in ImageFormat.values) {
        try {
          await _storage.ref('$prefix/$name.${f.extension}').delete();
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

  /// Confere o que dá para conferir antes de gastar a rede do usuário.
  ///
  /// Delega ao [ImageValidator], que é a mesma regra aplicada na entrada do
  /// pipeline. Antes existia uma segunda cópia aqui — outro teto de tamanho,
  /// outra lista de formatos, outra leitura de assinatura — e duas cópias de
  /// uma regra são duas regras esperando para divergir.
  ///
  /// As Storage Rules continuam sendo a autoridade: isto evita a viagem, não
  /// substitui a autorização.
  ImageFormat _validate(Uint8List bytes) {
    final ImageValidationResult r = const ImageValidator().validate(bytes);
    if (r.isValid) return r.format!;
    throw AppFailure(
      kind: FailureKind.validation,
      message: r.message,
      code: r.code.name,
    );
  }

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
