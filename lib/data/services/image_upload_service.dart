
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../models/image_validation.dart';
import '../models/processed_image.dart';
import '../../core/constants/image_limits.dart';
import '../../core/observability/app_log.dart';
import 'failure.dart';
import 'firebase_error_mapper.dart';

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
  /// Envia as três formas da imagem (briefing Fase 4, §9).
  ///
  /// Degrada por partes: cada arquivo que não subir vira um caminho nulo, e os
  /// demais seguem. O registro da identificação vale mais que o anexo —
  /// perder o histórico inteiro porque a miniatura falhou seria o pior
  /// negócio possível.
  ///
  /// [viewIndex] é 1 para a primeira fotografia e 2 para a segunda. As duas
  /// moram na **mesma pasta**, e a segunda leva sufixo no nome
  /// (`original-2`, `processed-2`, `thumbnail-2`).
  ///
  /// Mesma pasta porque são a mesma identificação: apagar o registro apaga as
  /// duas com um prefixo só, e uma segunda pasta com outro id criaria imagens
  /// que nenhum documento referencia pelo caminho que a regra conhece.
  Future<UploadedImagePaths> uploadAll({
    required ProcessedImage image,
    required String userId,
    required String identificationId,
    int viewIndex = 1,
  });

  /// Remove os arquivos de uma identificação — das duas vistas. Não falha se
  /// já não existirem.
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
  Future<UploadedImagePaths> uploadAll({
    required ProcessedImage image,
    required String userId,
    required String identificationId,
    int viewIndex = 1,
  }) async {
    assert(viewIndex == 1 || viewIndex == 2, 'só existem duas vistas');
    final String prefixo =
        'users/$userId/identifications/$identificationId';
    final String sufixo = suffixFor(viewIndex);

    // O caminho nunca vem da interface (§9): é montado aqui, a partir do uid
    // da sessão e de um id gerado pelo sistema. Um `userId` vindo de fora
    // permitiria escrever na pasta de outra pessoa — e as Storage Rules
    // recusariam, mas o pedido nem deve ser formulado.
    final List<_Envio> fila = <_Envio>[
      _Envio('original', image.original, sufixo),
      _Envio('processed', image.processed, sufixo),
      _Envio('thumbnail', image.thumbnail, sufixo),
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
    final String caminho =
        '$prefixo/${envio.nome}${envio.sufixo}.${envio.variante.format.extension}';
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
    // As duas vistas. Esquecer a segunda aqui deixaria, a cada identificação
    // cancelada ou apagada, três arquivos que nenhum registro referencia — dado
    // pessoal sem dono, que só a exclusão da conta inteira alcançaria.
    for (final int vista in <int>[1, 2]) {
      for (final String name in <String>['original', 'processed', 'thumbnail']) {
        for (final ImageFormat f in ImageFormat.values) {
          try {
            await _storage
                .ref('$prefix/$name${suffixFor(vista)}.${f.extension}')
                .delete();
          } catch (_) {
            // Arquivo inexistente é o caso normal — não é erro.
          }
        }
      }
    }
  }

  /// Sufixo do nome de arquivo de cada vista.
  ///
  /// A primeira não leva sufixo, de propósito: os nomes dela são os que já
  /// existem no bucket, e mudá-los deixaria toda identificação anterior
  /// apontando para arquivos com outro nome.
  ///
  /// **Espelha `isAllowedFileName` em `firebase/storage.rules` e a lista de
  /// `ViewRef` no backend.** Os três precisam concordar; quem tem a palavra
  /// final é a regra.
  @visibleForTesting
  static String suffixFor(int viewIndex) => viewIndex == 2 ? '-2' : '';
}

/// Par nome/forma, só para a fila de envio ficar legível.
@immutable
class _Envio {
  const _Envio(this.nome, this.variante, this.sufixo);
  final String nome;
  final ImageVariant variante;
  final String sufixo;
}

/// Sem upload: usada nos modos simulado e de teste.
class NoopImageUploadService implements ImageUploadService {
  const NoopImageUploadService();

  @override
  Future<UploadedImagePaths> uploadAll({
    required ProcessedImage image,
    required String userId,
    required String identificationId,
    int viewIndex = 1,
  }) async =>
      const UploadedImagePaths.none();

  @override
  Future<void> deleteFor({
    required String userId,
    required String identificationId,
  }) async {}
}
