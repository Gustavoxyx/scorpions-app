import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scorpions/core/constants/image_limits.dart';
import 'package:scorpions/core/utils/usage_day.dart';

void main() {
  group('UsageDay', () {
    test('conta dias inteiros desde a época, em UTC', () {
      expect(UsageDay.of(DateTime.utc(1970)), '0');
      expect(UsageDay.of(DateTime.utc(1970, 1, 2)), '1');
      expect(UsageDay.of(DateTime.utc(1970, 1, 2, 23, 59, 59)), '1');
      expect(UsageDay.of(DateTime.utc(1970, 1, 3)), '2');
    });

    test('o fuso do aparelho não muda o dia', () {
      // 22h em Brasília já é o dia seguinte em UTC. As regras contam em UTC, e
      // um aparelho contando no próprio fuso discordaria delas toda noite.
      final DateTime utc = DateTime.utc(2026, 10, 8, 1);
      final DateTime local = utc.toLocal();
      expect(UsageDay.of(local), UsageDay.of(utc));
    });

    test('bate com a conta que as regras fazem', () {
      // utcDay() nas regras: floor(millis / 86400000).
      final DateTime instante = DateTime.utc(2026, 10, 7, 15, 30);
      final int esperado = instante.millisecondsSinceEpoch ~/ 86400000;
      expect(UsageDay.of(instante), '$esperado');
    });
  });

  group('o limite diário é o mesmo nos três lugares', () {
    // O aplicativo avisa, as regras impedem e o backend limita as análises.
    // Se um dos três mudar sozinho, o usuário vê uma mensagem que não
    // corresponde ao que o servidor faz.
    test('nas Security Rules', () {
      final String regras = File('firebase/firestore.rules').readAsStringSync();
      final RegExpMatch? m = RegExp(
        r'function dailyCreationLimit\(\) \{\s*return (\d+);',
      ).firstMatch(regras);

      expect(m, isNotNull, reason: 'dailyCreationLimit() não foi encontrada');
      expect(int.parse(m!.group(1)!), ImageLimits.maxIdentificationsPerDay);
    });

    test('no backend', () {
      final String config = File('backend/app/config.py').readAsStringSync();
      final RegExpMatch? m =
          RegExp(r'max_analyses_per_day: int = (\d+)').firstMatch(config);

      expect(m, isNotNull, reason: 'max_analyses_per_day não foi encontrado');
      expect(int.parse(m!.group(1)!), ImageLimits.maxIdentificationsPerDay);
    });
  });
}
