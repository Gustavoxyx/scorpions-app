import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../../core/constants/image_limits.dart';
import '../models/image_quality.dart';

/// Avalia se a fotografia tem condição de ser analisada (briefing §5).
///
/// # O que este serviço é
/// Uma primeira implementação funcional, honesta sobre o que mede: brilho,
/// contraste e nitidez, calculados sobre os pixels. Não é visão computacional
/// e não pretende ser.
///
/// # Por que estatística simples resolve por enquanto
/// Os três defeitos que mais inviabilizam a identificação em campo — foto
/// escura, foto contra o sol e foto tremida — aparecem nessas medidas de forma
/// clara. Os que ela não pega (animal pequeno demais no quadro, corpo
/// parcialmente escondido) exigem saber onde o animal está, e isso é o
/// detector da Fase 5. Preferimos deixar esses campos nulos a estimá-los mal.
///
/// # Como trocar depois
/// A interface recebe uma imagem e devolve [ImageQualityResult]. Um modelo de
/// visão que substitua esta implementação continua devolvendo o mesmo tipo, e
/// o pipeline não muda.
abstract interface class ImageQualityService {
  ImageQualityResult assess(img.Image image);
}

class StatisticalImageQualityService implements ImageQualityService {
  const StatisticalImageQualityService();

  @override
  ImageQualityResult assess(img.Image image) {
    // Medimos numa cópia reduzida. Brilho, contraste e nitidez são
    // estatísticas da distribuição de luminância e sobrevivem à redução; o
    // custo cai cerca de 40x em relação a percorrer a imagem de 1600px.
    final img.Image amostra = _reduzir(image, ImageLimits.analysisDimension);
    final List<double> luz = _luminancia(amostra);

    final double brilho = _media(luz);
    final double contraste = _desvioPadrao(luz, brilho);
    final double nitidez = _nitidez(luz, amostra.width, amostra.height);

    final List<ImageQualityWarning> avisos = <ImageQualityWarning>[];
    if (brilho < ImageLimits.minBrightness) {
      avisos.add(ImageQualityWarning.tooDark);
    }
    if (brilho > ImageLimits.maxBrightness) {
      avisos.add(ImageQualityWarning.tooBright);
    }
    if (contraste < ImageLimits.minContrast) {
      avisos.add(ImageQualityWarning.lowContrast);
    }
    if (nitidez < ImageLimits.minSharpness) {
      avisos.add(ImageQualityWarning.blurry);
    } else if (nitidez < ImageLimits.warnSharpness) {
      avisos.add(ImageQualityWarning.softFocus);
    }
    // A validação já barrou o que é curto demais; aqui o aviso é sobre
    // conforto de análise, não sobre aceitação.
    final int ladoCurto = math.min(image.width, image.height);
    if (ladoCurto < 720) {
      avisos.add(ImageQualityWarning.lowResolution);
    }

    final double nota = _nota(
      brilho: brilho,
      contraste: contraste,
      nitidez: nitidez,
      ladoCurto: ladoCurto,
    );

    return ImageQualityResult(
      quality: _veredito(
        nota: nota,
        brilho: brilho,
        contraste: contraste,
        avisos: avisos,
      ),
      score: nota,
      brightness: brilho,
      contrast: contraste,
      sharpness: nitidez,
      width: image.width,
      height: image.height,
      warnings: List<ImageQualityWarning>.unmodifiable(avisos),
    );
  }

  // -- Veredito ---------------------------------------------------------------

  /// `invalid` é reservado ao que **nenhuma** análise salvaria: quadro preto,
  /// branco estourado ou completamente chapado. Foto tremida não entra aqui de
  /// propósito — ela é `poor`, e o §6 manda oferecer "continuar mesmo assim".
  /// Bloquear o usuário por desfoque seria decidir por ele numa medida que
  /// ainda é aproximada.
  ImageQuality _veredito({
    required double nota,
    required double brilho,
    required double contraste,
    required List<ImageQualityWarning> avisos,
  }) {
    final bool quadroMorto =
        brilho < 0.06 || brilho > 0.96 || contraste < 0.02;
    if (quadroMorto) return ImageQuality.invalid;
    if (nota < 0.45) return ImageQuality.poor;
    if (nota < 0.72 || avisos.isNotEmpty) return ImageQuality.acceptable;
    return ImageQuality.good;
  }

  /// Nota agregada.
  ///
  /// A nitidez pesa mais que o resto porque é o defeito que o classificador
  /// menos perdoa: contraste e brilho ainda deixam textura recuperável, borrão
  /// destrói a informação.
  double _nota({
    required double brilho,
    required double contraste,
    required double nitidez,
    required int ladoCurto,
  }) {
    const double alvoBrilho = 0.5;
    final double notaBrilho =
        (1 - (brilho - alvoBrilho).abs() / alvoBrilho).clamp(0.0, 1.0);
    final double notaContraste =
        (contraste / (ImageLimits.minContrast * 3)).clamp(0.0, 1.0);
    final double notaNitidez =
        (nitidez / ImageLimits.warnSharpness).clamp(0.0, 1.0);
    final double notaResolucao = (ladoCurto / 1080).clamp(0.0, 1.0);

    return (notaNitidez * 0.45 +
            notaBrilho * 0.25 +
            notaContraste * 0.20 +
            notaResolucao * 0.10)
        .clamp(0.0, 1.0);
  }

  // -- Medidas ----------------------------------------------------------------

  static img.Image _reduzir(img.Image image, int lado) {
    final int maior = math.max(image.width, image.height);
    if (maior <= lado) return image;
    return img.copyResize(
      image,
      width: image.width >= image.height ? lado : null,
      height: image.height > image.width ? lado : null,
      interpolation: img.Interpolation.average,
    );
  }

  /// Luminância perceptual (Rec. 601), normalizada de 0 a 1.
  ///
  /// Os coeficientes não são iguais porque o olho não é: o verde carrega a
  /// maior parte da sensação de claridade. Usar a média simples de R, G e B
  /// classificaria errado justamente as fotos de escorpião amarelo sobre
  /// terra, que é o caso mais comum aqui.
  static List<double> _luminancia(img.Image image) {
    final List<double> saida = List<double>.filled(
      image.width * image.height,
      0,
      growable: false,
    );
    int i = 0;
    for (final img.Pixel p in image) {
      saida[i++] =
          (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) / 255.0;
    }
    return saida;
  }

  static double _media(List<double> v) {
    if (v.isEmpty) return 0;
    double soma = 0;
    for (final double x in v) {
      soma += x;
    }
    return soma / v.length;
  }

  static double _desvioPadrao(List<double> v, double media) {
    if (v.length < 2) return 0;
    double soma = 0;
    for (final double x in v) {
      final double d = x - media;
      soma += d * d;
    }
    return math.sqrt(soma / v.length);
  }

  /// Variância do laplaciano — a medida clássica de foco.
  ///
  /// O laplaciano responde a mudanças bruscas de intensidade, que é o que uma
  /// borda é. Imagem nítida tem muitas bordas fortes e variância alta; imagem
  /// borrada tem transições suaves e variância baixa.
  static double _nitidez(List<double> luz, int largura, int altura) {
    if (largura < 3 || altura < 3) return 0;

    final List<double> resposta = <double>[];
    for (int y = 1; y < altura - 1; y++) {
      for (int x = 1; x < largura - 1; x++) {
        final int i = y * largura + x;
        final double lap = 4 * luz[i] -
            luz[i - 1] -
            luz[i + 1] -
            luz[i - largura] -
            luz[i + largura];
        resposta.add(lap);
      }
    }
    final double media = _media(resposta);
    final double desvio = _desvioPadrao(resposta, media);
    return desvio * desvio;
  }
}
