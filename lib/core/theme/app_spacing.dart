import 'package:flutter/widgets.dart';

/// Escala de espacamento de 4pt. Nenhum "padding: 16" solto pelas telas.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;
  static const double giant = 64;

  /// Margem horizontal padrao do conteudo de tela.
  static const double screenGutter = lg;

  /// Espaco reservado acima da barra inferior para o conteudo nao colar nela.
  static const double bottomNavClearance = 104;

  static const EdgeInsets screen =
      EdgeInsets.symmetric(horizontal: screenGutter);

  static const EdgeInsets card = EdgeInsets.all(lg);
  static const EdgeInsets cardCompact = EdgeInsets.all(md);

  static const SizedBox gapXs = SizedBox(height: xs, width: xs);
  static const SizedBox gapSm = SizedBox(height: sm, width: sm);
  static const SizedBox gapMd = SizedBox(height: md, width: md);
  static const SizedBox gapLg = SizedBox(height: lg, width: lg);
  static const SizedBox gapXl = SizedBox(height: xl, width: xl);
  static const SizedBox gapXxl = SizedBox(height: xxl, width: xxl);
  static const SizedBox gapXxxl = SizedBox(height: xxxl, width: xxxl);
}
