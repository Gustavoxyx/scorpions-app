import 'package:flutter/material.dart';

import '../core/constants/app_config.dart';

/// Idiomas previstos. Só pt-BR está implementado na Fase 1; a lista existe
/// para que a tela de configurações mostre a intenção do produto.
enum AppLanguage {
  ptBr('Português (Brasil)', true),
  enUs('English (US)', false),
  esEs('Español', false);

  const AppLanguage(this.label, this.available);
  final String label;
  final bool available;
}

/// Preferências do usuário.
///
/// FASE 1: tudo em memória. A persistência (`shared_preferences` no
/// dispositivo, documento de perfil no Firestore) entra na Fase 3 substituindo
/// apenas o corpo dos setters — a UI já observa este controlador.
class SettingsController extends ChangeNotifier {
  ThemeMode _themeMode = _initialThemeMode();

  /// O tema claro é o principal do produto — a identidade é de caderno de
  /// campo científico. O escuro existe em paridade real e pode ser escolhido
  /// nas configurações; `ThemeMode.system` respeita o aparelho.
  ThemeMode get themeMode => _themeMode;

  static ThemeMode _initialThemeMode() => switch (AppConfig.initialTheme) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      };

  bool _notificationsEnabled = true;
  bool get notificationsEnabled => _notificationsEnabled;

  bool _analyticsEnabled = false;

  /// Desligado por padrão: coleta de dados é opt-in.
  bool get analyticsEnabled => _analyticsEnabled;

  AppLanguage _language = AppLanguage.ptBr;
  AppLanguage get language => _language;

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
  }

  void setNotificationsEnabled(bool value) {
    if (_notificationsEnabled == value) return;
    _notificationsEnabled = value;
    notifyListeners();
  }

  void setAnalyticsEnabled(bool value) {
    if (_analyticsEnabled == value) return;
    _analyticsEnabled = value;
    notifyListeners();
  }

  void setLanguage(AppLanguage language) {
    if (!language.available || _language == language) return;
    _language = language;
    notifyListeners();
  }
}
