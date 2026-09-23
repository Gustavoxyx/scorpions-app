import 'package:flutter/widgets.dart';

/// Elevações. No tema escuro a sombra é sutil: quem separa camadas é a cor da
/// superfície, não o borrão.
abstract final class AppShadows {
  static List<BoxShadow> level1(Brightness b) => <BoxShadow>[
        BoxShadow(
          color: b == Brightness.dark
              ? const Color(0x40000000)
              : const Color(0x0F0C1512),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> level2(Brightness b) => <BoxShadow>[
        BoxShadow(
          color: b == Brightness.dark
              ? const Color(0x59000000)
              : const Color(0x140C1512),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];

  static List<BoxShadow> level3(Brightness b) => <BoxShadow>[
        BoxShadow(
          color: b == Brightness.dark
              ? const Color(0x73000000)
              : const Color(0x1F0C1512),
          blurRadius: 40,
          offset: const Offset(0, 18),
        ),
      ];

  /// Halo do acento UV. Reservado à ação primária e ao logo.
  static List<BoxShadow> glow(Color color, {double strength = 1}) =>
      <BoxShadow>[
        BoxShadow(
          color: color.withValues(alpha: 0.28 * strength),
          blurRadius: 28 * strength,
          spreadRadius: -4,
          offset: const Offset(0, 6),
        ),
      ];
}
