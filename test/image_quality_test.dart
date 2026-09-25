import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:scorpions/data/models/image_quality.dart';
import 'package:scorpions/data/services/image_quality_service.dart';

/// Cena com estrutura em duas escalas: manchas largas mais textura fina.
///
/// Ruído puro não serve de referência — ele tem energia máxima em alta
/// frequência e faria qualquer medida de nitidez parecer excelente. Uma cena
/// com ondas largas e granulação fina aproxima muito melhor uma fotografia de
/// animal sobre substrato, que é o caso de uso real.
img.Image _cena({double luz = 1.0, int semente = 5, int lado = 800}) {
  final img.Image im = img.Image(width: lado, height: (lado * 0.75).round());
  final Random r = Random(semente);
  for (int y = 0; y < im.height; y++) {
    for (int x = 0; x < im.width; x++) {
      final double onda = 0.5 + 0.35 * sin(x / 40) * cos(y / 55);
      final double textura = r.nextDouble() * 0.25;
      final int v = ((onda + textura) * 200 * luz).clamp(0, 255).round();
      im.setPixelRgb(x, y, v, (v * 0.9).round(), (v * 0.7).round());
    }
  }
  return im;
}

img.Image _uniforme(int tom) {
  final img.Image im = img.Image(width: 800, height: 600);
  img.fill(im, color: img.ColorRgb8(tom, tom, tom));
  return im;
}

void main() {
  const StatisticalImageQualityService servico =
      StatisticalImageQualityService();

  group('nitidez', () {
    test('cena nítida não é acusada de desfoque', () {
      final ImageQualityResult r = servico.assess(_cena());
      expect(r.warnings, isNot(contains(ImageQualityWarning.blurry)));
      expect(r.quality, isNot(ImageQuality.poor));
      expect(r.score, greaterThan(0.7));
    });

    test('desfoque leve é detectado', () {
      final ImageQualityResult r =
          servico.assess(img.gaussianBlur(_cena(), radius: 2));
      expect(r.warnings, contains(ImageQualityWarning.blurry));
    });

    test('a medida cai monotonicamente conforme o borrão cresce', () {
      final double nitida = servico.assess(_cena()).sharpness;
      final double leve =
          servico.assess(img.gaussianBlur(_cena(), radius: 2)).sharpness;
      final double forte =
          servico.assess(img.gaussianBlur(_cena(), radius: 6)).sharpness;

      expect(nitida, greaterThan(leve));
      expect(leve, greaterThan(forte));
    });
  });

  group('exposição', () {
    test('foto escura recebe aviso, mas ainda é utilizável', () {
      final ImageQualityResult r = servico.assess(_cena(luz: 0.35));
      expect(r.warnings, contains(ImageQualityWarning.tooDark));
      expect(r.isUsable, isTrue, reason: 'escura demais ainda dá para tentar');
    });

    test('foto estourada recebe aviso', () {
      final ImageQualityResult r = servico.assess(_cena(luz: 2.2));
      expect(r.warnings, contains(ImageQualityWarning.tooBright));
    });
  });

  group('invalid é reservado ao que nenhuma análise salvaria', () {
    test('quadro preto', () {
      expect(servico.assess(_uniforme(0)).quality, ImageQuality.invalid);
    });

    test('quadro branco', () {
      expect(servico.assess(_uniforme(255)).quality, ImageQuality.invalid);
    });

    test('quadro chapado sem contraste', () {
      final ImageQualityResult r = servico.assess(_uniforme(128));
      expect(r.quality, ImageQuality.invalid);
      expect(r.warnings, contains(ImageQualityWarning.lowContrast));
    });

    test('desfoque forte é poor, não invalid', () {
      // Decisão de produto (§6): borrão é ruim, mas quem decide continuar é o
      // usuário. Bloquear seria decidir por ele com base numa medida que ainda
      // é aproximada.
      final ImageQualityResult r =
          servico.assess(img.gaussianBlur(_cena(), radius: 6));
      expect(r.quality, ImageQuality.poor);
      expect(r.isUsable, isTrue);
    });
  });

  group('contrato do resultado', () {
    test('campos que dependem de detecção ficam nulos, não inventados', () {
      final ImageQualityResult r = servico.assess(_cena());
      expect(r.subjectRatio, isNull);
      expect(r.isSubjectCentered, isNull);
      expect(r.isSubjectOccluded, isNull);
    });

    test('a forma persistida guarda as medidas, não só o veredito', () {
      final Map<String, Object?> m = servico.assess(_cena()).toMap();
      expect(m['quality'], isA<String>());
      expect(m['brightness'], isA<double>());
      expect(m['sharpness'], isA<double>());
      expect(m['warnings'], isA<List<String>>());
      expect(m['width'], 800);
    });

    test('toda combinação de aviso produz frase acionável', () {
      for (final ImageQualityWarning w in ImageQualityWarning.values) {
        expect(w.message.length, greaterThan(20));
        expect(w.message.endsWith('.'), isTrue);
      }
    });
  });
}
