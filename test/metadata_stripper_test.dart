import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:scorpions/data/services/metadata_stripper.dart';

img.Image _cena() {
  final img.Image im = img.Image(width: 320, height: 240);
  final Random r = Random(11);
  for (int y = 0; y < 240; y++) {
    for (int x = 0; x < 320; x++) {
      final int v = ((0.5 + 0.4 * sin(x / 12)) * 200 + r.nextInt(30))
          .clamp(0, 255)
          .round();
      im.setPixelRgb(x, y, v, 255 - v, (v * 1.3).clamp(0, 255).round());
    }
  }
  return im;
}

Uint8List _comExif() {
  final img.Image im = _cena();
  im.exif.imageIfd['Make'] = 'Aparelho de Teste';
  im.exif.imageIfd['Model'] = 'Modelo XYZ';
  // O que realmente importa esconder: onde a pessoa estava.
  im.exif.gpsIfd['GPSLatitudeRef'] = 'S';
  im.exif.gpsIfd['GPSLongitudeRef'] = 'W';
  return Uint8List.fromList(img.encodeJpg(im, quality: 90));
}

void main() {
  test('o JPEG de partida realmente carrega metadados', () {
    expect(
      MetadataStripper.hasMetadata(_comExif()),
      isTrue,
      reason: 'sem isso o teste seguinte não provaria nada',
    );
  });

  test('remove os metadados', () {
    final Uint8List limpo = MetadataStripper.strip(_comExif());
    expect(MetadataStripper.hasMetadata(limpo), isFalse);
  });

  test('o GPS não sobrevive em lugar nenhum do arquivo', () {
    final Uint8List limpo = MetadataStripper.strip(_comExif());
    // Procura a assinatura textual do bloco EXIF nos bytes crus.
    const List<int> marcaExif = <int>[0x45, 0x78, 0x69, 0x66]; // "Exif"
    bool contem = false;
    for (int i = 0; i + 3 < limpo.length; i++) {
      if (limpo[i] == marcaExif[0] &&
          limpo[i + 1] == marcaExif[1] &&
          limpo[i + 2] == marcaExif[2] &&
          limpo[i + 3] == marcaExif[3]) {
        contem = true;
        break;
      }
    }
    expect(contem, isFalse);

    final img.Image? relido = img.decodeJpg(limpo);
    expect(relido, isNotNull);
    expect(relido!.exif.gpsIfd.isEmpty, isTrue);
  });

  test('os pixels não são tocados — nenhuma recompressão', () {
    final Uint8List original = _comExif();
    final Uint8List limpo = MetadataStripper.strip(original);

    final img.Image a = img.decodeJpg(original)!;
    final img.Image b = img.decodeJpg(limpo)!;

    expect(b.width, a.width);
    expect(b.height, a.height);

    // Igualdade exata: recompressão mudaria estes valores.
    for (final List<int> ponto in <List<int>>[
      <int>[0, 0],
      <int>[160, 120],
      <int>[319, 239],
      <int>[75, 200],
    ]) {
      final img.Pixel pa = a.getPixel(ponto[0], ponto[1]);
      final img.Pixel pb = b.getPixel(ponto[0], ponto[1]);
      expect(<num>[pb.r, pb.g, pb.b], <num>[pa.r, pa.g, pa.b]);
    }
  });

  test('o arquivo limpo é menor', () {
    final Uint8List original = _comExif();
    expect(
      MetadataStripper.strip(original).length,
      lessThan(original.length),
    );
  });

  group('não estraga o que não entende', () {
    test('PNG passa intacto', () {
      final Uint8List png = Uint8List.fromList(img.encodePng(_cena()));
      expect(MetadataStripper.strip(png), same(png));
    });

    test('lixo passa intacto em vez de virar arquivo quebrado', () {
      final Uint8List lixo = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0x00, 0x99, 0x42]);
      expect(MetadataStripper.strip(lixo), same(lixo));
    });

    test('JPEG truncado no meio de um segmento devolve o original', () {
      final Uint8List completo = _comExif();
      final Uint8List cortado =
          Uint8List.sublistView(completo, 0, 40);
      expect(MetadataStripper.strip(cortado).length, cortado.length);
    });
  });

  group('leitura da etiqueta de orientação', () {
    test('devolve o valor gravado', () {
      for (final int o in <int>[1, 3, 6, 8]) {
        final img.Image im = _cena();
        im.exif.imageIfd.orientation = o;
        final Uint8List bytes =
            Uint8List.fromList(img.encodeJpg(im, quality: 90));
        expect(MetadataStripper.readJpegOrientation(bytes), o);
      }
    });

    test('devolve nulo quando não há EXIF', () {
      final Uint8List bytes =
          Uint8List.fromList(img.encodeJpg(_cena(), quality: 90));
      expect(MetadataStripper.readJpegOrientation(bytes), isNull);
    });

    test('devolve nulo em arquivo que não é JPEG', () {
      expect(
        MetadataStripper.readJpegOrientation(
            Uint8List.fromList(img.encodePng(_cena()))),
        isNull,
      );
    });

    test('não quebra com arquivo truncado', () {
      final img.Image im = _cena();
      im.exif.imageIfd.orientation = 6;
      final Uint8List completo =
          Uint8List.fromList(img.encodeJpg(im, quality: 90));
      for (final int corte in <int>[8, 20, 40, 100]) {
        expect(
          () => MetadataStripper.readJpegOrientation(
              Uint8List.sublistView(completo, 0, corte)),
          returnsNormally,
        );
      }
    });
  });

  test('o decodificador do pacote `image` já entrega os pixels de pé', () {
    // Comportamento de biblioteca, fixado aqui de propósito: o pipeline conta
    // com ele e não chama `bakeOrientation`. Se uma versão futura parar de
    // aplicar a orientação na decodificação, este teste falha e avisa.
    final img.Image im = _cena(); // 320x240
    im.exif.imageIfd.orientation = 6; // 90 graus
    final img.Image decodificada =
        img.decodeJpg(Uint8List.fromList(img.encodeJpg(im, quality: 90)))!;
    expect(decodificada.width, 240);
    expect(decodificada.height, 320);
  });
}
