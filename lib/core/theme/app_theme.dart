import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_motion.dart';
import 'app_radii.dart';
import 'app_sizing.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Monta os [ThemeData] a partir dos tokens.
///
/// Regra do projeto: telas e componentes leem cores e textos por
/// `context.colors` / `context.text`, nunca por `Colors.*` ou literais.
///
/// O tema claro é o principal do produto; o escuro é mantido em paridade real,
/// derivado dos mesmos tokens semânticos — nenhum widget precisa saber em qual
/// dos dois está.
abstract final class AppTheme {
  static ThemeData dark() => _build(AppColors.dark);

  static ThemeData light() => _build(AppColors.light);

  static ThemeData _build(AppColors c) {
    final AppTypography type =
        AppTypography.build(c.textPrimary, c.textSecondary);
    final ColorScheme scheme = ColorScheme(
      brightness: c.brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      secondary: c.secondary,
      onSecondary: c.onSecondary,
      error: c.error,
      onError: c.textInverse,
      surface: c.surface,
      onSurface: c.textPrimary,
      surfaceContainerHighest: c.surfaceVariant,
      outline: c.border,
      outlineVariant: c.borderStrong,
      shadow: const Color(0xFF000000),
      scrim: c.scrim,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: c.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      splashFactory: InkSparkle.splashFactory,
      extensions: <ThemeExtension<dynamic>>[c, type],
      textTheme: _textTheme(type),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: type.h3,
        systemOverlayStyle: c.brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      dividerTheme: DividerThemeData(
        color: c.border,
        thickness: AppSizing.hairline,
        space: AppSizing.hairline,
      ),
      iconTheme: IconThemeData(color: c.textSecondary, size: AppSizing.iconLg),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceVariant,
        contentTextStyle: type.bodySmall.copyWith(color: c.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.brSm),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: c.scrim,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceVariant,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.brLg),
        titleTextStyle: type.h3,
        contentTextStyle: type.body,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
            s.contains(WidgetState.selected) ? c.onPrimary : c.textTertiary),
        trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
            s.contains(WidgetState.selected) ? c.primary : c.surfaceSunken),
        trackOutlineColor: WidgetStateProperty.resolveWith((Set<WidgetState> s) =>
            s.contains(WidgetState.selected) ? c.primary : c.borderStrong),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.primary,
        inactiveTrackColor: c.surfaceSunken,
        thumbColor: c.primary,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.surfaceSunken,
        circularTrackColor: c.surfaceSunken,
      ),
      splashColor: c.primary.withValues(alpha: 0.08),
      highlightColor: c.primary.withValues(alpha: 0.04),
      visualDensity: VisualDensity.standard,
    );
  }

  /// Mapeia a escala do produto para os slots do Material.
  ///
  /// Existe para que widgets do framework (diálogos, tooltips, snackbars)
  /// herdem a nossa tipografia sem que precisemos estilizar cada um.
  static TextTheme _textTheme(AppTypography t) => TextTheme(
        displayLarge: t.display,
        displayMedium: t.h1,
        headlineLarge: t.h1,
        headlineMedium: t.h2,
        headlineSmall: t.h3,
        titleLarge: t.h3,
        titleMedium: t.h4,
        titleSmall: t.label,
        bodyLarge: t.body,
        bodyMedium: t.body,
        bodySmall: t.bodySmall,
        labelLarge: t.label,
        labelMedium: t.labelSmall,
        labelSmall: t.overline,
      );
}

/// Açúcar sintático usado por toda a UI.
extension AppThemeContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  AppTypography get text => Theme.of(this).extension<AppTypography>()!;

  /// Largura útil da tela — base das decisões responsivas.
  double get screenWidth => MediaQuery.sizeOf(this).width;
  double get screenHeight => MediaQuery.sizeOf(this).height;

  /// Telas estreitas (Android pequeno, 320–360dp): menos respiro, títulos
  /// menores, grades com menos colunas.
  bool get isCompact => screenWidth < AppSizing.breakpointCompact;

  /// Tablets e telas grandes: conteúdo centralizado e limitado.
  bool get isExpanded => screenWidth >= AppSizing.breakpointExpanded;

  /// Telas baixas: ilustrações e áreas decorativas precisam encolher para não
  /// empurrar o conteúdo essencial para fora da dobra.
  bool get isShort => screenHeight < AppSizing.breakpointShort;

  /// O produto é mobile: em telas largas mantemos uma única coluna centralizada
  /// em vez de esticar o layout até virar um site.
  double get maxContentWidth =>
      isExpanded ? AppSizing.maxContentWidth : double.infinity;

  /// Movimento reduzido pedido pelo sistema operacional (acessibilidade).
  bool get reduceMotion => MediaQuery.disableAnimationsOf(this);
}

/// Constantes de animação reexportadas para conveniência dos widgets.
typedef Motion = AppMotion;
typedef Space = AppSpacing;
