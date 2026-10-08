import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../core/constants/image_limits.dart';
import '../models/image_quality.dart';
import '../models/image_validation.dart';
import '../models/processed_image.dart';
import 'image_quality_service.dart';
import 'image_validator.dart';
import 'metadata_stripper.dart';

/// Prepara a imagem para análise e armazenamento (briefing Fase 4, §7).
///
/// # Uma passada só
/// Validar, medir qualidade e derivar as três formas acontecem numa única
/// decodificação. Não é microtimização: decodificar uma foto de 12 MP custa
/// ~48 MB de heap e centenas de milissegundos: repetir isso três vezes num
/// aparelho de entrada é a diferença entre responder e ser encerrado pelo
/// sistema.
///
/// # Fora da thread de interface
/// O trabalho roda em [compute], que no Android e no iOS despacha para um
/// isolate de verdade. **Na web não existe isolate** e o `compute` executa na
/// mesma thread — a interface trava durante o processamento. É por isso que os
/// limites de dimensão existem e são conservadores; fingir paralelismo que a
/// plataforma não tem seria pior que assumir o custo.
abstract interface class ImageProcessingService {
  /// Valida, mede e deriva. Nunca lança por imagem ruim — uma imagem recusada
  /// é um resultado, não uma exceção.
  Future<ImagePreparation> prepare(Uint8List bytes);
}

class DefaultImageProcessingService implements ImageProcessingService {
  const DefaultImageProcessingService();

  @override
  Future<ImagePreparation> prepare(Uint8List bytes) {
    return compute(runPipeline, bytes);
  }

  /// A passada completa, síncrona.
  ///
  /// Estática e pura para que sirva de ponto de entrada do isolate **e** possa
  /// ser testada direto, sem infraestrutura de concorrência no meio.
  @visibleForTesting
  static ImagePreparation runPipeline(Uint8List bytes) {
    const ImageValidator validador = ImageValidator();
    final ImageValidationResult validacao = validador.validate(bytes);
    if (!validacao.isValid) return ImagePreparation.rejected(validacao);

    final img.Image? decodificada = _decodificar(bytes);
    if (decodificada == null) {
      return ImagePreparation.rejected(
        ImageValidationResult.rejected(
          ImageValidationCode.corrupted,
          format: validacao.format,
          byteCount: bytes.length,
        ),
      );
    }

    // O decodificador do pacote `image` **já entrega os pixels de pé**: ele
    // aplica a etiqueta de orientação na decodificação. Isso está coberto por
    // teste, porque é comportamento de biblioteca e pode mudar de versão.
    //
    // O que **não** está de pé são os bytes do arquivo de origem. Por isso
    // perguntamos ao arquivo, e não à imagem, se havia rotação pendente.
    final img.Image endireitada = decodificada;
    final int orientacao = MetadataStripper.readJpegOrientation(bytes) ?? 1;
    final bool precisaGirar = orientacao != 1;

    // Sem isto, `encodeJpg` regravaria o EXIF que acabamos de decidir remover.
    endireitada.exif = img.ExifData();

    const ImageQualityService medidor = StatisticalImageQualityService();
    final ImageQualityResult qualidade = medidor.assess(endireitada);

    // O arquivo pedia rotação? Apagar o EXIF apagaria esse pedido junto e
    // deixaria o original deitado, então ali a recompressão é obrigatória.
    //
    // Fora isso, os metadados saem sem tocar nos pixels — em JPEG, PNG e WebP.
    // `strip` devolve nulo quando não consegue GARANTIR que o arquivo saiu
    // limpo (formato fora do padrão, bloco truncado), e esse caso também é
    // recomprimido: perde um pouco de qualidade, mas não sobe com a localização
    // de alguém dentro.
    final Uint8List? limpo = precisaGirar ? null : MetadataStripper.strip(bytes);

    final ImageVariant original = limpo == null
        ? _encodar(endireitada, ImageLimits.originalQuality)
        : ImageVariant(
            bytes: limpo,
            width: endireitada.width,
            height: endireitada.height,
            format: validacao.format ?? ImageFormat.jpeg,
          );

    final img.Image reduzida = _reduzir(
      endireitada,
      ImageLimits.processedMaxDimension,
    );
    final ImageVariant processada = _encodar(
      reduzida,
      ImageLimits.processedQuality,
    );

    // A miniatura sai da imagem JÁ REDUZIDA, não do original.
    //
    // O custo de `copyResize` com `average` cresce com o fator de redução,
    // porque a janela amostrada por pixel de destino cresce com ele. Produzir
    // 320px a partir de 4000 amostra ~156 pixels por destino; a partir de
    // 1600, ~25.
    //
    // Medido em `benchmark/image_pipeline_benchmark.dart`, a partir de
    // 4000×3000, em duas execuções:
    //
    //     4000 → 320  (como era antes)    901 ms / 840 ms
    //     1600 → 320  (como é agora)      115 ms / 134 ms
    //
    // Economia de ~700 a 790 ms por fotografia — e a Fase 5 manda duas.
    //
    // E a qualidade? É a pergunta que decide, porque média de médias *pode*
    // borrar. Medido no mesmo arquivo: diferença média de **0,34 de 255** por
    // canal, e nitidez (variância do laplaciano, o mesmo indicador que
    // `ImageQualityService` usa para julgar foco) em **99,7%** da direta.
    // Indistinguível.
    //
    // Ressalva honesta: a cena do benchmark é sintética. Para medir tempo isso
    // não importa — o custo depende da contagem de pixels, igual à de uma foto
    // do mesmo tamanho. Para qualidade percebida, confirmar com fotografia de
    // campo fica pendente.
    final ImageVariant miniatura = _encodar(
      _reduzir(reduzida, ImageLimits.thumbnailMaxDimension),
      ImageLimits.thumbnailQuality,
    );

    return ImagePreparation(
      validation: validacao,
      quality: qualidade,
      image: ProcessedImage(
        original: original,
        processed: processada,
        thumbnail: miniatura,
        originalWasReencoded: limpo == null,
      ),
    );
  }

  // -- Interno ----------------------------------------------------------------

  static img.Image? _decodificar(Uint8List bytes) {
    try {
      return img.decodeImage(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Reduz preservando proporção. Imagem já pequena passa direto — ampliar
  /// não cria detalhe, só peso.
  static img.Image _reduzir(img.Image image, int ladoMaximo) {
    final int maior = math.max(image.width, image.height);
    if (maior <= ladoMaximo) return image;
    final bool larga = image.width >= image.height;
    return img.copyResize(
      image,
      width: larga ? ladoMaximo : null,
      height: larga ? null : ladoMaximo,
      // `average` amostra a vizinhança inteira ao encolher. `nearest` seria
      // mais rápido e produziria serrilhado, que o classificador leria como
      // textura que não existe.
      interpolation: img.Interpolation.average,
    );
  }

  static ImageVariant _encodar(img.Image image, int qualidade) {
    return ImageVariant(
      bytes: Uint8List.fromList(img.encodeJpg(image, quality: qualidade)),
      width: image.width,
      height: image.height,
      format: ImageFormat.jpeg,
    );
  }
}
