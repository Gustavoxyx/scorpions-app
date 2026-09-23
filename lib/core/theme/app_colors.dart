import 'package:flutter/material.dart';

/// Paleta semântica do produto.
///
/// # Conceito
/// *Caderno de campo científico.* O tema claro é o principal: papel off-white
/// levemente quente, verde-musgo profundo como cor de autoridade e ocre de
/// terra como secundária. O tema escuro é o mesmo caderno sob luz de campo
/// noturno — mesma estrutura, mesma semântica, nunca outro produto.
///
/// # Regra de nomenclatura
/// Os nomes descrevem **significado**, não cor. `error` sobrevive a uma troca
/// de vermelho; `danger` ou `red` não. Widgets nunca escrevem `Colors.*`.
///
/// # Confiança da IA
/// `confidenceHigh/Medium/Low/None` são derivados de `success/warning/error`.
/// Ficam aqui — e não dentro de um widget — porque são **regra de produto**:
/// a mesma faixa precisa ter a mesma cor no resultado, no histórico e na ficha.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.surfaceSunken,
    required this.border,
    required this.borderStrong,
    required this.primary,
    required this.primaryStrong,
    required this.primarySoft,
    required this.onPrimary,
    required this.secondary,
    required this.secondarySoft,
    required this.onSecondary,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.error,
    required this.errorSoft,
    required this.info,
    required this.infoSoft,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textInverse,
    required this.onMedia,
    required this.onMediaDim,
    required this.overlay,
    required this.scrim,
  });

  final Brightness brightness;

  // -- Superfícies ------------------------------------------------------------

  /// Fundo da aplicação. O "papel".
  final Color background;

  /// Superfície de cards e folhas.
  final Color surface;

  /// Superfície alternativa: card sobre card, cabeçalhos, menus.
  final Color surfaceVariant;

  /// Superfície rebaixada: campos de entrada, trilhos, poços.
  final Color surfaceSunken;

  final Color border;
  final Color borderStrong;

  // -- Cor de marca -----------------------------------------------------------

  /// Verde-musgo. Cor de autoridade: ação principal e sinais positivos.
  final Color primary;

  /// Variante pressionada/enfática do primary.
  final Color primaryStrong;

  /// Fundo translúcido do primary, para badges e realces.
  final Color primarySoft;

  final Color onPrimary;

  /// Ocre de terra. Acento orgânico: atenção, categorias, contraponto quente.
  final Color secondary;
  final Color secondarySoft;
  final Color onSecondary;

  // -- Sinais semânticos ------------------------------------------------------

  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color error;
  final Color errorSoft;
  final Color info;
  final Color infoSoft;

  // -- Texto ------------------------------------------------------------------

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// Texto sobre superfícies de cor cheia (primary, error).
  final Color textInverse;

  // -- Sobre mídia ------------------------------------------------------------

  /// Texto e ícones sobre fotografia ou visor de câmera.
  ///
  /// Existe como token porque sobre uma foto o contraste **não** segue o tema:
  /// é sempre claro. Antes isto era `Colors.white` espalhado pela câmera.
  final Color onMedia;
  final Color onMediaDim;

  /// Véu sobre imagens, para garantir legibilidade do texto.
  final Color overlay;

  /// Fundo de diálogos e folhas modais.
  final Color scrim;

  bool get isDark => brightness == Brightness.dark;

  // -- Faixas de confiança da IA ---------------------------------------------
  // Derivadas: a semântica de "quanto o sistema confia" é a mesma de
  // "está tudo bem / atenção / problema".

  Color get confidenceHigh => success;
  Color get confidenceMedium => warning;
  Color get confidenceLow => error;
  Color get confidenceNone => textTertiary;

  Color get confidenceHighSoft => successSoft;
  Color get confidenceMediumSoft => warningSoft;
  Color get confidenceLowSoft => errorSoft;
  Color get confidenceNoneSoft => surfaceSunken;

  // ==========================================================================
  // TEMA CLARO — principal
  // ==========================================================================
  //
  // O off-white é levemente quente (não cinza) para lembrar papel. O verde
  // primário é escuro o bastante para passar em contraste AA sobre ele, o que
  // permite usá-lo em texto de link e não apenas em botões.

  static const AppColors light = AppColors(
    brightness: Brightness.light,
    background: Color(0xFFF7F6F1),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFF1F0E9),
    surfaceSunken: Color(0xFFEAE8DF),
    border: Color(0xFFE1DFD3),
    borderStrong: Color(0xFFC8C5B5),
    primary: Color(0xFF14593F),
    primaryStrong: Color(0xFF0D4029),
    primarySoft: Color(0x1A14593F),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFF9A6224),
    secondarySoft: Color(0x1A9A6224),
    onSecondary: Color(0xFFFFFFFF),
    success: Color(0xFF14593F),
    successSoft: Color(0x1A14593F),
    warning: Color(0xFF9A6224),
    warningSoft: Color(0x1A9A6224),
    error: Color(0xFFA83A2C),
    errorSoft: Color(0x1AA83A2C),
    info: Color(0xFF1C6480),
    infoSoft: Color(0x1A1C6480),
    textPrimary: Color(0xFF14201A),
    textSecondary: Color(0xFF4C5A52),
    textTertiary: Color(0xFF7A877F),
    textInverse: Color(0xFFFFFFFF),
    onMedia: Color(0xFFFFFFFF),
    onMediaDim: Color(0xB3FFFFFF),
    overlay: Color(0x8A14201A),
    scrim: Color(0x9914201A),
  );

  // ==========================================================================
  // TEMA ESCURO — paridade real
  // ==========================================================================
  //
  // Não é o tema claro invertido: o verde precisa clarear bastante para manter
  // contraste sobre fundo escuro, e as superfícies se separam por luminância,
  // não por sombra. O acento evoca a fluorescência do exoesqueleto sob luz UV,
  // mas puxado deliberadamente para longe do neon.

  static const AppColors dark = AppColors(
    brightness: Brightness.dark,
    background: Color(0xFF0B100D),
    surface: Color(0xFF131A16),
    surfaceVariant: Color(0xFF1B241E),
    surfaceSunken: Color(0xFF090D0B),
    border: Color(0xFF222E27),
    borderStrong: Color(0xFF334138),
    primary: Color(0xFF4CCB92),
    primaryStrong: Color(0xFF6FDCAB),
    primarySoft: Color(0x244CCB92),
    onPrimary: Color(0xFF05150E),
    secondary: Color(0xFFD79F5E),
    secondarySoft: Color(0x24D79F5E),
    onSecondary: Color(0xFF1A1206),
    success: Color(0xFF4CCB92),
    successSoft: Color(0x244CCB92),
    warning: Color(0xFFD79F5E),
    warningSoft: Color(0x24D79F5E),
    error: Color(0xFFE0705F),
    errorSoft: Color(0x24E0705F),
    info: Color(0xFF63C2E8),
    infoSoft: Color(0x2463C2E8),
    textPrimary: Color(0xFFE8EFEA),
    textSecondary: Color(0xFF9DAEA4),
    textTertiary: Color(0xFF6D7E74),
    textInverse: Color(0xFF05150E),
    onMedia: Color(0xFFFFFFFF),
    onMediaDim: Color(0xB3FFFFFF),
    overlay: Color(0x990B100D),
    scrim: Color(0xCC050907),
  );

  @override
  AppColors copyWith({
    Brightness? brightness,
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? surfaceSunken,
    Color? border,
    Color? borderStrong,
    Color? primary,
    Color? primaryStrong,
    Color? primarySoft,
    Color? onPrimary,
    Color? secondary,
    Color? secondarySoft,
    Color? onSecondary,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? error,
    Color? errorSoft,
    Color? info,
    Color? infoSoft,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textInverse,
    Color? onMedia,
    Color? onMediaDim,
    Color? overlay,
    Color? scrim,
  }) {
    return AppColors(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      primary: primary ?? this.primary,
      primaryStrong: primaryStrong ?? this.primaryStrong,
      primarySoft: primarySoft ?? this.primarySoft,
      onPrimary: onPrimary ?? this.onPrimary,
      secondary: secondary ?? this.secondary,
      secondarySoft: secondarySoft ?? this.secondarySoft,
      onSecondary: onSecondary ?? this.onSecondary,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      error: error ?? this.error,
      errorSoft: errorSoft ?? this.errorSoft,
      info: info ?? this.info,
      infoSoft: infoSoft ?? this.infoSoft,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textInverse: textInverse ?? this.textInverse,
      onMedia: onMedia ?? this.onMedia,
      onMediaDim: onMediaDim ?? this.onMediaDim,
      overlay: overlay ?? this.overlay,
      scrim: scrim ?? this.scrim,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: c(background, other.background),
      surface: c(surface, other.surface),
      surfaceVariant: c(surfaceVariant, other.surfaceVariant),
      surfaceSunken: c(surfaceSunken, other.surfaceSunken),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      primary: c(primary, other.primary),
      primaryStrong: c(primaryStrong, other.primaryStrong),
      primarySoft: c(primarySoft, other.primarySoft),
      onPrimary: c(onPrimary, other.onPrimary),
      secondary: c(secondary, other.secondary),
      secondarySoft: c(secondarySoft, other.secondarySoft),
      onSecondary: c(onSecondary, other.onSecondary),
      success: c(success, other.success),
      successSoft: c(successSoft, other.successSoft),
      warning: c(warning, other.warning),
      warningSoft: c(warningSoft, other.warningSoft),
      error: c(error, other.error),
      errorSoft: c(errorSoft, other.errorSoft),
      info: c(info, other.info),
      infoSoft: c(infoSoft, other.infoSoft),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      textInverse: c(textInverse, other.textInverse),
      onMedia: c(onMedia, other.onMedia),
      onMediaDim: c(onMediaDim, other.onMediaDim),
      overlay: c(overlay, other.overlay),
      scrim: c(scrim, other.scrim),
    );
  }
}
