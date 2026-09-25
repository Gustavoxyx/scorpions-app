
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../models/captured_image.dart';
import '../models/image_validation.dart';
import '../models/processed_image.dart';
import '../../core/constants/image_limits.dart';
import '../../core/observability/app_log.dart';
import 'failure.dart';
import 'firebase_error_mapper.dart';
import 'image_bytes_reader.dart';
import 'image_validator.dart';

/// Envio das fotografias para o Cloud Storage (brief §14, §16).
/// Onde cada forma da imagem foi parar.
///
/// Nulo significa "não subiu" — seja porque o bucket não existe, seja porque
/// a rede caiu no meio. A interface já sabe desenhar os três casos, porque
/// é o mesmo estado do modo simulado.
@immutable
class UploadedImagePaths {
  const UploadedImagePaths({this.original, this.processed, this.thumbnail});

  const UploadedImagePaths.none()
      : original = null,
        processed = null,
        thumbnail = null;

  final String? original;
  final String? processed;
  final String? thumbnail;

  bool get isEmpty => original == null && processed == null && thumbnail == null;

  /// Caminho que a análise deve consumir, com queda para o original.
  String? get forAnalysis => processed ?? original;

  int get uploadedCount =>
      (original != null ? 1 : 0) +
      (processed != null ? 1 : 0) +
      (thumbnail != null ? 1 : 0);
}

abstract interface class ImageUploadService {
  /// Envia a imagem e devolve o caminho gravado no documento.
  Future<String?> upload({
    required CapturedImage image,
    required String userId,
    required String identificationId,
  });

  /// Envia as três formas da imagem (briefing Fase 4, §9).
  ///
  /// Degrada por partes: cada arquivo que não subir vira um caminho nulo, e os
  /// demais seguem. O registro da identificação vale mais que o anexo —
  /// perder o histórico inteiro porque a miniatura falhou seria o pior
  /// negócio possível.
  Future<UploadedImagePaths> uploadAll({
    required ProcessedImage image,
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

    final Uint8List bytes = await readImageBytes(image);
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
  Future<UploadedImagePaths> uploadAll({
    required ProcessedImage image,
    required String userId,
    required String identificationId,
  }) async {
    final String prefixo =
        'users/$userId/identifications/$identificationId';

    // O caminho nunca vem da interface (§9): é montado aqui, a partir do uid
    // da sessão e de um id gerado pelo sistema. Um `userId` vindo de fora
    // permitiria escrever na pasta de outra pessoa — e as Storage Rules
    // recusariam, mas o pedido nem deve ser formulado.
    final List<_Envio> fila = <_Envio>[
      _Envio('original', image.original),
      _Envio('processed', image.processed),
      _Envio('thumbnail', image.thumbnail),
    ];

    final Map<String, String?> feitos = <String, String?>{};
    // Em lotes, e não todos de uma vez: três envios simultâneos numa rede
    // móvel disputam a mesma banda e costumam terminar depois do que dois.
    for (int i = 0; i < fila.length; i += ImageLimits.maxConcurrentUploads) {
      final List<_Envio> lote =
          fila.skip(i).take(ImageLimits.maxConcurrentUploads).toList();
      final List<String?> r = await Future.wait(
        lote.map((_Envio e) => _enviarOuNulo(prefixo, e)),
      );
      for (int k = 0; k < lote.length; k++) {
        feitos[lote[k].nome] = r[k];
      }
    }

    return UploadedImagePaths(
      original: feitos['original'],
      processed: feitos['processed'],
      thumbnail: feitos['thumbnail'],
    );
  }

  /// Envia uma forma. Devolve `null` em vez de propagar, para que a falha de
  /// um arquivo não leve os outros junto.
  Future<String?> _enviarOuNulo(String prefixo, _Envio envio) async {
    final String caminho = '$prefixo/${envio.nome}.${envio.variante.format.extension}';
    try {
      return await FirebaseErrorMapper.guard(
        () async {
          await _storage.ref(caminho).putData(
                envio.variante.bytes,
                SettableMetadata(
                  contentType: envio.variante.format.mimeType,
                  customMetadata: <String, String>{'variant': envio.nome},
                ),
              );
          return caminho;
        },
        timeout: const Duration(seconds: 90),
      );
    } on AppFailure catch (f) {
      AppLog.event(AppEvent.uploadSkipped, <String, Object?>{
        'variant': envio.nome,
        'reason': f.code ?? f.kind.name,
      });
      return null;
    }
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

/// Par nome/forma, só para a fila de envio ficar legível.
@immutable
class _Envio {
  const _Envio(this.nome, this.variante);
  final String nome;
  final ImageVariant variante;
}

/// Sem upload: usada nos modos simulado e de teste.
class NoopImageUploadService implements ImageUploadService {
  const NoopImageUploadService();

  @override
  Future<UploadedImagePaths> uploadAll({
    required ProcessedImage image,
    required String userId,
    required String identificationId,
  }) async =>
      const UploadedImagePaths.none();

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
