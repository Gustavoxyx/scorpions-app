import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:scorpions/core/constants/image_limits.dart';

/// Mede o custo de derivar as variantes de imagem.
///
/// # Por que este arquivo existe
/// `DefaultImageProcessingService.runPipeline` decodifica a foto **uma** vez —
/// isso está certo e documentado. Mas depois deriva as duas reduções a partir
/// da imagem em tamanho original:
///
///     original (ex. 4000×3000)  ──copyResize──►  processada (1600)
///     original (ex. 4000×3000)  ──copyResize──►  miniatura  (320)
///
/// A hipótese da auditoria era que derivar a miniatura **da processada** (que
/// já tem 1600px) sairia mais barato, por percorrer 2,5 milhões de pixels em
/// vez de 12 milhões.
///
/// A medida disse o contrário, e este arquivo ficou para registrar por quê: o
/// custo de `copyResize` com `Interpolation.average` **não** é proporcional ao
/// tamanho da origem. Ele é proporcional ao número de pixels de destino
/// multiplicado pela área da janela amostrada, e essa janela cresce com o
/// fator de redução. Reduzir 4000→320 (fator 12,5) amostra ~156 pixels por
/// destino; reduzir 1600→320 (fator 5) amostra ~25. Mas o passo intermediário
/// 4000→1600 produz 1600×1200 destinos, cada um amostrando ~6 pixels — e é
/// esse passo, não o final, que domina a conta.
///
/// Em outras palavras: a cascata **paga duas reamostragens caras** onde a forma
/// atual paga uma cara e uma barata.
///
/// O §41 do briefing pede exatamente isto — "Isso está causando X porque Y" —
/// e o §54 proíbe otimizar por achismo. A hipótese era plausível e estava
/// errada; o pipeline fica como está.
///
///     flutter test benchmark/image_pipeline_benchmark.dart
void main() {
  /// Cena sintética com textura em várias frequências.
  ///
  /// Não é uma foto, e isso limita o que o teste pode afirmar sobre qualidade
  /// percebida. Mas para medir **tempo** de reamostragem o que conta é a
  /// contagem de pixels, idêntica à de uma foto do mesmo tamanho.
  img.Image cena(int largura, int altura) {
    final img.Image imagem = img.Image(width: largura, height: altura);
    for (int y = 0; y < altura; y++) {
      for (int x = 0; x < largura; x++) {
        final int base = (x * 255 ~/ largura);
        final int xadrez = ((x ~/ 3) + (y ~/ 3)) % 2 == 0 ? 40 : 0;
        final int onda = (40 * math.sin(y / 7.0)).round();
        imagem.setPixelRgb(
          x,
          y,
          (base + xadrez).clamp(0, 255),
          (base ~/ 2 + onda).clamp(0, 255),
          (255 - base + xadrez).clamp(0, 255),
        );
      }
    }
    return imagem;
  }

  img.Image reduzir(img.Image imagem, int ladoMaximo) {
    final int maior = math.max(imagem.width, imagem.height);
    if (maior <= ladoMaximo) return imagem;
    final bool larga = imagem.width >= imagem.height;
    return img.copyResize(
      imagem,
      width: larga ? ladoMaximo : null,
      height: larga ? null : ladoMaximo,
      interpolation: img.Interpolation.average,
    );
  }

  /// Melhor tempo de [repeticoes] execuções, não a média.
  ///
  /// O menor tempo observado é o mais próximo do custo do código; a média mede
  /// também o escalonador do sistema e a coleta de lixo.
  Duration medir(String rotulo, int repeticoes, void Function() acao) {
    acao(); // aquece
    Duration melhor = const Duration(days: 1);
    for (int i = 0; i < repeticoes; i++) {
      final Stopwatch cronometro = Stopwatch()..start();
      acao();
      cronometro.stop();
      if (cronometro.elapsed < melhor) melhor = cronometro.elapsed;
    }
    // ignore: avoid_print
    print('  $rotulo: ${melhor.inMilliseconds} ms');
    return melhor;
  }

  test('custo de cada reamostragem, isolada', () {
    final img.Image original = cena(4000, 3000);
    final img.Image intermediaria =
        reduzir(original, ImageLimits.processedMaxDimension);

    // ignore: avoid_print
    print('\n--- cada passo isolado ---');

    final Duration grandeParaMedia =
        medir('4000 → 1600  (o passo da processada)', 5, () {
      reduzir(original, ImageLimits.processedMaxDimension);
    });

    final Duration grandeParaPequena =
        medir('4000 →  320  (miniatura como é hoje)', 5, () {
      reduzir(original, ImageLimits.thumbnailMaxDimension);
    });

    final Duration mediaParaPequena =
        medir('1600 →  320  (miniatura em cascata)', 5, () {
      reduzir(intermediaria, ImageLimits.thumbnailMaxDimension);
    });

    final int hoje =
        grandeParaMedia.inMilliseconds + grandeParaPequena.inMilliseconds;
    final int cascata =
        grandeParaMedia.inMilliseconds + mediaParaPequena.inMilliseconds;

    // ignore: avoid_print
    print(
      '\n  total hoje    (4000→1600 + 4000→320): $hoje ms'
      '\n  total cascata (4000→1600 + 1600→320): $cascata ms'
      '\n'
      '\n  CONCLUSÃO: ${cascata < hoje ? "a cascata compensa" : "a cascata NÃO compensa"}'
      '\n  O passo 4000→1600 custa ${grandeParaMedia.inMilliseconds} ms e'
      ' aparece nas duas formas, então não é ele que decide.'
      '\n  O que decide é 4000→320 (${grandeParaPequena.inMilliseconds} ms)'
      ' contra 1600→320 (${mediaParaPequena.inMilliseconds} ms).\n',
    );

    // Sem asserção de qual é mais rápido: o teste existe para medir, e um
    // limite inventado aqui transformaria a medição numa profecia.
    expect(grandeParaMedia, greaterThan(Duration.zero));
  });

  test('a miniatura em cascata não fica pior que a direta', () {
    // Registrado mesmo com a troca descartada: se algum dia o reamostrador
    // mudar e a cascata passar a compensar, a pergunta de qualidade já está
    // respondida e medida.
    final img.Image original = cena(4000, 3000);

    final img.Image direta =
        reduzir(original, ImageLimits.thumbnailMaxDimension);
    final img.Image cascata = reduzir(
      reduzir(original, ImageLimits.processedMaxDimension),
      ImageLimits.thumbnailMaxDimension,
    );

    expect(cascata.width, direta.width, reason: 'dimensões precisam bater');
    expect(cascata.height, direta.height);

    double soma = 0;
    int contagem = 0;
    for (int y = 0; y < direta.height; y++) {
      for (int x = 0; x < direta.width; x++) {
        final img.Pixel a = direta.getPixel(x, y);
        final img.Pixel b = cascata.getPixel(x, y);
        soma += (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();
        contagem += 3;
      }
    }
    final double diferencaMedia = soma / contagem;

    /// Variância do laplaciano — o mesmo indicador que `ImageQualityService`
    /// usa para julgar foco. Se a cascata borrasse a miniatura, cairia aqui.
    double nitidez(img.Image imagem) {
      double somaQuadrados = 0;
      int pontos = 0;
      for (int y = 1; y < imagem.height - 1; y++) {
        for (int x = 1; x < imagem.width - 1; x++) {
          final num centro = imagem.getPixel(x, y).luminanceNormalized;
          final num lap = 4 * centro -
              imagem.getPixel(x - 1, y).luminanceNormalized -
              imagem.getPixel(x + 1, y).luminanceNormalized -
              imagem.getPixel(x, y - 1).luminanceNormalized -
              imagem.getPixel(x, y + 1).luminanceNormalized;
          somaQuadrados += lap * lap;
          pontos++;
        }
      }
      return somaQuadrados / pontos;
    }

    final double nitidezDireta = nitidez(direta);
    final double nitidezCascata = nitidez(cascata);

    // ignore: avoid_print
    print(
      '\n--- qualidade da miniatura ${direta.width}×${direta.height} ---\n'
      '  diferença média por canal: ${diferencaMedia.toStringAsFixed(2)} de 255\n'
      '  nitidez direta:  ${nitidezDireta.toStringAsFixed(6)}\n'
      '  nitidez cascata: ${nitidezCascata.toStringAsFixed(6)}\n'
      '  razão: ${(nitidezCascata / nitidezDireta).toStringAsFixed(3)}\n',
    );

    expect(
      diferencaMedia,
      lessThan(4.0),
      reason: 'as miniaturas divergiram visivelmente',
    );
    expect(
      nitidezCascata / nitidezDireta,
      greaterThan(0.75),
      reason: 'a cascata borrou a miniatura',
    );
  });
}
