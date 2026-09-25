import 'package:flutter/foundation.dart';

/// Por que uma imagem foi aceita ou recusada (briefing Fase 4, §4).
///
/// Códigos, não frases: a mensagem exibida é derivada daqui, e quem decide o
/// texto é a camada de apresentação. Isso mantém a regra testável sem depender
/// de string de interface.
enum ImageValidationCode {
  valid,

  /// Nenhum byte — arquivo vazio ou leitura falhou no meio.
  empty,

  /// Abaixo de `ImageLimits.minBytes`.
  tooSmall,

  /// Acima de `ImageLimits.maxBytes`.
  tooLarge,

  /// Os primeiros bytes não são de imagem nenhuma. Extensão mente; assinatura
  /// binária, não.
  invalidFormat,

  /// É imagem, mas de um formato que o pipeline não trata (GIF, BMP, TIFF).
  unsupported,

  /// Cabeçalho legível, conteúdo não. Arquivo truncado ou corrompido.
  corrupted,

  /// Menor que `ImageLimits.minDimension` no lado curto.
  tooFewPixels,

  /// Maior que `ImageLimits.maxDimension` — decodificar arriscaria a memória.
  tooManyPixels,
}

/// Formatos que o pipeline sabe ler e reencodar.
enum ImageFormat {
  jpeg('image/jpeg', 'jpg'),
  png('image/png', 'png'),
  webp('image/webp', 'webp');

  const ImageFormat(this.mimeType, this.extension);

  final String mimeType;
  final String extension;
}

/// Veredito da validação.
@immutable
class ImageValidationResult {
  const ImageValidationResult._({
    required this.code,
    this.format,
    this.width,
    this.height,
    this.byteCount,
  });

  factory ImageValidationResult.valid({
    required ImageFormat format,
    required int width,
    required int height,
    required int byteCount,
  }) {
    return ImageValidationResult._(
      code: ImageValidationCode.valid,
      format: format,
      width: width,
      height: height,
      byteCount: byteCount,
    );
  }

  factory ImageValidationResult.rejected(
    ImageValidationCode code, {
    ImageFormat? format,
    int? width,
    int? height,
    int? byteCount,
  }) {
    assert(code != ImageValidationCode.valid, 'Recusa exige um código de erro.');
    return ImageValidationResult._(
      code: code,
      format: format,
      width: width,
      height: height,
      byteCount: byteCount,
    );
  }

  final ImageValidationCode code;

  /// Conhecido a partir da assinatura binária, não da extensão do arquivo.
  final ImageFormat? format;

  final int? width;
  final int? height;
  final int? byteCount;

  bool get isValid => code == ImageValidationCode.valid;

  /// Lado curto, que é o que os limites de dimensão governam.
  int? get shortestSide {
    final int? w = width;
    final int? h = height;
    if (w == null || h == null) return null;
    return w < h ? w : h;
  }

  /// Texto para o usuário.
  ///
  /// Nunca nomeia classe, código interno ou exceção (§16). Cada frase diz o
  /// que houve **e** o que fazer a respeito — um erro que não sugere ação é
  /// só uma porta fechada.
  String get message => switch (code) {
        ImageValidationCode.valid => 'Imagem válida.',
        ImageValidationCode.empty =>
          'Não conseguimos ler essa imagem. Tente escolher ou tirar outra.',
        ImageValidationCode.tooSmall =>
          'Esse arquivo é pequeno demais para ser uma fotografia. '
              'Tente tirar a foto pelo aplicativo.',
        ImageValidationCode.tooLarge =>
          'A imagem é grande demais. Fotografe pelo aplicativo, que já '
              'reduz o arquivo para o tamanho certo.',
        ImageValidationCode.invalidFormat =>
          'Esse arquivo não parece ser uma imagem.',
        ImageValidationCode.unsupported =>
          'Esse formato de imagem não é aceito. Use uma foto em JPG ou PNG.',
        ImageValidationCode.corrupted =>
          'A imagem parece estar danificada. Tente tirar outra foto.',
        ImageValidationCode.tooFewPixels =>
          'A resolução é baixa demais para analisar os detalhes do animal. '
              'Aproxime-se e fotografe novamente.',
        ImageValidationCode.tooManyPixels =>
          'A imagem tem resolução alta demais para ser processada aqui. '
              'Fotografe pelo aplicativo.',
      };

  @override
  String toString() =>
      'ImageValidationResult(${code.name}, ${width}x$height, $byteCount B)';
}
