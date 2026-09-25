import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:scorpions/core/constants/image_limits.dart';
import 'package:scorpions/data/models/image_validation.dart';
import 'package:scorpions/data/models/processed_image.dart';
import 'package:scorpions/data/services/image_processing_service.dart';
import 'package:scorpions/data/services/metadata_stripper.dart';

img.Image _cena({int largura = 2400, int altura = 1800}) {
  final img.Image im = img.Image(width: largura, height: altura);
  final Random r = Random(23);
  for (int y = 0; y < altura; y++) {
    for (int x = 0; x < largura; x++) {
      final double onda = 0.5 + 0.35 * sin(x / 60) * cos(y / 70);
      final int v =
          ((onda + r.nextDouble() * 0.2) * 210).clamp(0, 255).round();
      im.setPixelRgb(x, y, v, (v * 0.85).round(), (v * 0.6).round());
    }
  }
  return im;
}

Uint8List _jpeg(img.Image im, {int? orientacao, bool gps = true}) {
  if (gps) {
    im.exif.imageIfd['Make'] = 'Aparelho de Teste';
    im.exif.gpsIfd['GPSLatitudeRef'] = 'S';
  }
  if (orientacao != null) {
    // Pelo setter dedicado, não pelo mapa: `imageIfd['Orientation'] = 6` não
    // sobrevive ao encode nesta versão do pacote `image`.
    im.exif.imageIfd.orientation = orientacao;
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 90));
}

void main() {
  group('imagem válida', () {
    late ImagePreparation p;

    setUpAll(() {
      p = DefaultImageProcessingService.runPipeline(_jpeg(_cena()));
    });

    test('produz as três formas', () {
      expect(p.isValid, isTrue);
      expect(p.canProceed, isTrue);
      expect(p.image, isNotNull);
      expect(p.quality, isNotNull);
    });

    test('a processada respeita o teto de dimensão', () {
      final ImageVariant v = p.image!.processed;
      expect(max(v.width, v.height), ImageLimits.processedMaxDimension);
      expect(v.format, ImageFormat.jpeg);
    });

    test('a miniatura respeita o teto de dimensão', () {
      final ImageVariant v = p.image!.thumbnail;
      expect(max(v.width, v.height), ImageLimits.thumbnailMaxDimension);
    });

    test('cada forma é menor que a anterior', () {
      final ProcessedImage im = p.image!;
      expect(im.thumbnail.byteCount, lessThan(im.processed.byteCount));
      expect(im.processed.byteCount, lessThan(im.original.byteCount));
    });

    test('nenhuma das três carrega metadado', () {
      for (final ImageVariant v in <ImageVariant>[
        p.image!.original,
        p.image!.processed,
        p.image!.thumbnail,
      ]) {
        expect(MetadataStripper.hasMetadata(v.bytes), isFalse);
        expect(img.decodeJpg(v.bytes)!.exif.gpsIfd.isEmpty, isTrue);
      }
    });

    test('a qualidade foi medida sobre a imagem inteira, não sobre a reduzida',
        () {
      expect(p.quality!.width, 2400);
      expect(p.quality!.height, 1800);
    });
  });

  group('orientação', () {
    test('sem etiqueta, o original preserva os bytes — não recomprime', () {
      final ImagePreparation p =
          DefaultImageProcessingService.runPipeline(_jpeg(_cena(largura: 1200, altura: 900)));
      expect(p.image!.originalWasReencoded, isFalse);
      expect(p.image!.original.width, 1200);
    });

    test('com etiqueta de 90°, os pixels são girados e as dimensões trocam',
        () {
      final Uint8List bytes =
          _jpeg(_cena(largura: 1200, altura: 900), orientacao: 6);
      final ImagePreparation p =
          DefaultImageProcessingService.runPipeline(bytes);

      expect(p.image!.originalWasReencoded, isTrue,
          reason: 'girar obriga a reencodar; o registro precisa dizer isso');
      expect(p.image!.original.width, 900);
      expect(p.image!.original.height, 1200);
      expect(p.quality!.width, 900);
    });
  });

  group('recusa', () {
    test('imagem pequena demais não chega a ser processada', () {
      final ImagePreparation p = DefaultImageProcessingService.runPipeline(
        _jpeg(_cena(largura: 200, altura: 150), gps: false),
      );
      expect(p.isValid, isFalse);
      expect(p.canProceed, isFalse);
      expect(p.image, isNull);
      expect(p.quality, isNull,
          reason: 'medir qualidade do que já foi recusado é trabalho jogado');
    });

    test('arquivo que não é imagem', () {
      final Uint8List lixo = Uint8List(ImageLimits.minBytes * 2);
      lixo[0] = 0x25;
      lixo[1] = 0x50;
      final ImagePreparation p =
          DefaultImageProcessingService.runPipeline(lixo);
      expect(p.validation.code, ImageValidationCode.invalidFormat);
    });
  });
}
