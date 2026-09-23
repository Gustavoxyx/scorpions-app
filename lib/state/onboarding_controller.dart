import 'package:flutter/foundation.dart';

import '../core/constants/app_config.dart';

/// Controla se a apresentação inicial já foi vista.
///
/// FASE 1: memória. Na Fase 3 o valor vem de `shared_preferences` e a única
/// mudança é o corpo de [complete] e a leitura inicial — o roteador continua
/// observando este objeto.
class OnboardingController extends ChangeNotifier {
  /// Já nasce concluído no build de demonstração
  /// (`--dart-define=DEMO_AUTOLOGIN=true`), que abre direto na Home.
  bool _completed = AppConfig.demoAutoLogin;

  bool get completed => _completed;

  void complete() {
    if (_completed) return;
    _completed = true;
    notifyListeners();
  }

  /// Usado pela tela "Sobre" para rever a apresentação.
  void replay() {
    if (!_completed) return;
    _completed = false;
    notifyListeners();
  }
}
