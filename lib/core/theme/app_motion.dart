import 'package:flutter/animation.dart';

/// Durações e curvas centralizadas. Microinterações novas devem consumir estes
/// tokens em vez de inventar números — é o que mantém um único ritmo no app.
abstract final class AppMotion {
  /// Feedback imediato de toque.
  static const Duration instant = Duration(milliseconds: 90);

  /// Mudança de estado local (cor, escala de botão).
  static const Duration fast = Duration(milliseconds: 150);

  /// Padrão para transições de conteúdo.
  static const Duration base = Duration(milliseconds: 250);

  /// Transições de página.
  static const Duration page = Duration(milliseconds: 320);

  /// Entradas encadeadas e revelações.
  static const Duration slow = Duration(milliseconds: 450);

  /// Sequência de descoberta da tela de resultado.
  static const Duration reveal = Duration(milliseconds: 620);

  /// Atraso entre itens de uma entrada escalonada.
  static const Duration stagger = Duration(milliseconds: 70);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Cubic(0.2, 0, 0, 1);
  static const Curve decelerate = Curves.easeOutQuart;
  static const Curve spring = Curves.easeOutBack;
}
