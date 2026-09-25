import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:scorpions/core/constants/image_limits.dart';
import 'package:scorpions/data/models/image_validation.dart';
import 'package:scorpions/data/services/image_validator.dart';

/// As imagens são geradas aqui, não versionadas como arquivos binários.
///
/// Motivo: um `.jpg` no repositório não conta o que testa. `_ruido(400, 400)`
/// diz, no nome, que aquele caso é "resolução curta demais" — e ninguém
/// precisa abrir um arquivo para descobrir por que o teste existe.
Uint8List _ruido(int largura, int altura, {int semente = 7}) {
  final img.Image image = img.Image(width: largura, height: altura);
  final Random r = Random(semente);
  for (int y = 0; y < altura; y++) {
    for (int x = 0; x < largura; x++) {
      image.setPixelRgb(x, y, r.nextInt(256), r.nextInt(256), r.nextInt(256));
    }
  }
  // Ruído não comprime: garante folga sobre o piso de bytes.
  return Uint8List.fromList(img.encodeJpg(image, quality: 92));
}

/// Gradiente: muitos pixels, poucos bytes. É como se chega a uma imagem de
/// dimensão enorme sem estourar o teto de tamanho.
Uint8List _gradiente(int largura, int altura) {
  final img.Image image = img.Image(width: largura, height: altura);
  for (int x = 0; x < largura; x++) {
    final int tom = (255 * x / largura).round();
    img.drawLine(
      image,
      x1: x,
      y1: 0,
      x2: x,
      y2: altura - 1,
      color: img.ColorRgb8(tom, 255 - tom, (tom * 2) % 256),
    );
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 80));
}

Uint8List _comCabecalho(List<int> assinatura) {
  final Uint8List b = Uint8List(ImageLimits.minBytes * 2);
  for (int i = 0; i < assinatura.length; i++) {
    b[i] = assinatura[i];
  }
  return b;
}

void main() {
  const ImageValidator validator = ImageValidator();

  group('aceita', () {
    test('JPEG dentro dos limites', () {
      final ImageValidationResult r = validator.validate(_ruido(800, 600));
      expect(r.code, ImageValidationCode.valid);
      expect(r.format, ImageFormat.jpeg);
      expect(r.width, 800);
      expect(r.height, 600);
      expect(r.shortestSide, 600);
    });

    test('PNG dentro dos limites', () {
      final img.Image image = img.Image(width: 640, height: 640);
      final Random r = Random(3);
      for (int y = 0; y < 640; y++) {
        for (int x = 0; x < 640; x++) {
          image.setPixelRgb(x, y, r.nextInt(256), r.nextInt(256), r.nextInt(256));
        }
      }
      final ImageValidationResult res =
          validator.validate(Uint8List.fromList(img.encodePng(image)));
      expect(res.code, ImageValidationCode.valid);
      expect(res.format, ImageFormat.png);
    });
  });

  group('recusa por tamanho', () {
    test('vazia', () {
      expect(
        validator.validate(Uint8List(0)).code,
        ImageValidationCode.empty,
      );
    });

    test('poucos bytes para ser fotografia', () {
      // Imagem legítima, porém minúscula: cai no piso de bytes.
      expect(
        validator.validate(_ruido(24, 24)).code,
        ImageValidationCode.tooSmall,
      );
    });

    test('acima do teto de 8 MB', () {
      final Uint8List gigante = Uint8List(ImageLimits.maxBytes + 1);
      gigante[0] = 0xFF;
      gigante[1] = 0xD8;
      gigante[2] = 0xFF;
      expect(
        validator.validate(gigante).code,
        ImageValidationCode.tooLarge,
        reason: 'o teto precisa ser conferido antes de qualquer decodificação',
      );
    });
  });

  group('recusa por formato', () {
    test('arquivo que não é imagem', () {
      // "%PDF"
      expect(
        validator.validate(_comCabecalho(<int>[0x25, 0x50, 0x44, 0x46])).code,
        ImageValidationCode.invalidFormat,
      );
    });

    test('GIF é imagem, mas não tratamos', () {
      final ImageValidationResult r =
          validator.validate(_comCabecalho(<int>[0x47, 0x49, 0x46, 0x38]));
      expect(r.code, ImageValidationCode.unsupported);
      expect(
        r.message,
        contains('JPG'),
        reason: 'a mensagem precisa dizer o que fazer, não só o que falhou',
      );
    });

    test('HEIC do iPhone cai em não suportado, não em arquivo inválido', () {
      final Uint8List b = _comCabecalho(<int>[0, 0, 0, 0x18]);
      b[4] = 0x66; // f
      b[5] = 0x74; // t
      b[6] = 0x79; // y
      b[7] = 0x70; // p
      expect(validator.validate(b).code, ImageValidationCode.unsupported);
    });

    test('assinatura de JPEG com conteúdo lixo é corrompida', () {
      final Uint8List b = _comCabecalho(<int>[0xFF, 0xD8, 0xFF, 0xE0]);
      expect(validator.validate(b).code, ImageValidationCode.corrupted);
    });
  });

  group('recusa por dimensão', () {
    test('lado curto abaixo do mínimo', () {
      final ImageValidationResult r = validator.validate(_ruido(400, 400));
      expect(r.code, ImageValidationCode.tooFewPixels);
      expect(r.width, 400, reason: 'a dimensão medida entra no resultado');
    });

    test('lado longo acima do máximo', () {
      final ImageValidationResult r = validator.validate(_gradiente(6100, 520));
      expect(r.code, ImageValidationCode.tooManyPixels);
      expect(r.height, 520);
    });
  });

  test('nenhuma mensagem vaza nome interno ao usuário', () {
    for (final ImageValidationCode code in ImageValidationCode.values) {
      final String m = ImageValidationResult.rejected(
        code == ImageValidationCode.valid ? ImageValidationCode.empty : code,
      ).message;
      expect(m, isNot(contains('Exception')));
      expect(m, isNot(contains('_')));
      expect(m.endsWith('.'), isTrue, reason: 'frase completa: "$m"');
    }
  });
}
