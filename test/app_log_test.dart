
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scorpions/core/observability/app_log.dart';

void main() {
  test('registra evento com medidas derivadas', () {
    expect(
      () => AppLog.event(AppEvent.imageQualityChecked,
          <String, Object?>{'quality': 'good', 'score': 0.82, 'ms': 412}),
      returnsNormally,
    );
  });

  group('a trava do §27 impede o descuido', () {
    test('chave proibida derruba em depuração', () {
      for (final String chave in <String>['email', 'token', 'password', 'uid', 'url']) {
        expect(
          () => AppLog.event(AppEvent.identificationCreated, <String, Object?>{chave: 'x'}),
          throwsA(isA<FlutterError>()),
          reason: 'a chave "$chave" nao pode passar',
        );
      }
    });

    test('variação de grafia não escapa', () {
      // `userId`, `user-id`, `USER_ID` sao a mesma chave proibida.
      for (final String chave in <String>['userId', 'user-id', 'USER_ID', 'E-Mail']) {
        expect(
          () => AppLog.event(AppEvent.uploadStarted, <String, Object?>{chave: 'x'}),
          throwsA(isA<FlutterError>()),
          reason: chave,
        );
      }
    });

    test('bytes de imagem nunca entram', () {
      expect(
        () => AppLog.event(AppEvent.uploadStarted,
            <String, Object?>{'conteudo': Uint8List(10)}),
        throwsA(isA<FlutterError>()),
      );
    });

    test('valor longo é barrado — log guarda medida, não conteúdo', () {
      expect(
        () => AppLog.event(AppEvent.pipelineFailed,
            <String, Object?>{'motivo': 'x' * 200}),
        throwsA(isA<FlutterError>()),
      );
    });
  });

  test('todo evento tem identificador em snake_case', () {
    for (final AppEvent e in AppEvent.values) {
      expect(e.id, matches(RegExp(r'^[a-z]+(_[a-z]+)*$')), reason: e.name);
    }
  });
}
