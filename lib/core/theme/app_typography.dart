import 'package:flutter/material.dart';

/// Escala tipográfica do produto.
///
/// # Por que não `google_fonts`
/// Aquele pacote baixa arquivos de fonte em tempo de execução: dependência de
/// rede e um flash de fonte na primeira abertura. Ficamos na fonte do sistema
/// (San Francisco no iOS, Roboto no Android) e concentramos a personalidade em
/// peso, escala e tracking. Para empacotar uma fonte depois, declare a família
/// no `pubspec.yaml` e preencha [fontFamily] — nenhuma tela muda.
///
/// # A escala tem degraus pequenos de propósito
/// A auditoria da Fase 1 encontrou 15 `fontSize:` avulsos (8, 9, 9.5, 10, 11,
/// 12). Não era desleixo: a escala não tinha degraus micro, então cada tela
/// inventava o seu. [caption], [micro], [overlineSmall] e [monoSmall] fecham
/// esse buraco — se um tamanho é necessário, ele vira token.
@immutable
class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({
    required this.display,
    required this.h1,
    required this.h2,
    required this.h3,
    required this.h4,
    required this.body,
    required this.bodySmall,
    required this.caption,
    required this.micro,
    required this.label,
    required this.labelSmall,
    required this.overline,
    required this.overlineSmall,
    required this.mono,
    required this.monoSmall,
    required this.scientificNameHero,
    required this.scientificName,
    required this.scientificNameSmall,
  });

  /// Família tipográfica global. `null` = fonte padrão da plataforma.
  static const String? fontFamily = null;

  /// Fallback serifado dos nomes científicos.
  ///
  /// A serifa é o que faz o binômio latino "parecer ciência": é a convenção
  /// tipográfica da literatura taxonômica desde Lineu.
  static const List<String> serifFallback = <String>[
    'Georgia',
    'Iowan Old Style',
    'Times New Roman',
    'serif',
  ];

  // -- Títulos ----------------------------------------------------------------

  /// Números e frases de impacto. Um por tela, no máximo.
  final TextStyle display;

  final TextStyle h1;
  final TextStyle h2;
  final TextStyle h3;

  /// Título de card e de linha de lista.
  final TextStyle h4;

  // -- Corpo ------------------------------------------------------------------

  final TextStyle body;
  final TextStyle bodySmall;

  /// Legenda, metadado, texto de apoio sob um campo.
  final TextStyle caption;

  /// Menor tamanho legível do sistema. Só para etiquetas dentro de gráficos e
  /// ilustrações — nunca para texto que o usuário precise ler de fato.
  final TextStyle micro;

  // -- Controles --------------------------------------------------------------

  final TextStyle label;
  final TextStyle labelSmall;

  /// Caixa alta com tracking largo: rótulo de instrumento científico.
  /// É o que dá ao app o ar de etiqueta de coleção.
  final TextStyle overline;
  final TextStyle overlineSmall;

  // -- Números ----------------------------------------------------------------

  /// Algarismos tabulares: confiança, datas, contagens.
  /// Tabular impede que o número "dance" enquanto o valor anima.
  final TextStyle mono;
  final TextStyle monoSmall;

  // -- Nome científico --------------------------------------------------------

  /// Tratamento próprio do binômio latino (brief §8), em três degraus.
  ///
  /// Itálico + serifa + tracking levemente aberto. Não é "só um título em
  /// itálico": é o elemento que sinaliza que o app fala a linguagem da
  /// taxonomia, e ele aparece igual no resultado, no catálogo e na ficha.
  ///
  /// Herói da tela de resultado — o momento da descoberta.
  final TextStyle scientificNameHero;

  /// Cabeçalho da ficha da espécie.
  final TextStyle scientificName;

  /// Título de cartão e de linha de lista.
  final TextStyle scientificNameSmall;

  static AppTypography build(Color primary, Color secondary) {
    TextStyle s({
      required double size,
      required FontWeight weight,
      required double height,
      double tracking = 0,
      Color? color,
    }) {
      return TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: tracking,
        color: color ?? primary,
      );
    }

    TextStyle numeric({required double size}) => TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: FontWeight.w600,
          height: 1.2,
          letterSpacing: 0.2,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          color: primary,
        );

    TextStyle latin({required double size, required FontWeight weight}) =>
        TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: serifFallback,
          fontSize: size,
          fontWeight: weight,
          fontStyle: FontStyle.italic,
          height: 1.24,
          letterSpacing: 0.1,
          color: primary,
        );

    return AppTypography(
      display:
          s(size: 34, weight: FontWeight.w700, height: 1.10, tracking: -0.9),
      h1: s(size: 28, weight: FontWeight.w700, height: 1.16, tracking: -0.6),
      h2: s(size: 22, weight: FontWeight.w700, height: 1.22, tracking: -0.35),
      h3: s(size: 18, weight: FontWeight.w600, height: 1.28, tracking: -0.2),
      h4: s(size: 15, weight: FontWeight.w600, height: 1.32),
      body: s(size: 15, weight: FontWeight.w400, height: 1.58, color: secondary),
      bodySmall:
          s(size: 13, weight: FontWeight.w400, height: 1.52, color: secondary),
      caption:
          s(size: 12, weight: FontWeight.w400, height: 1.42, color: secondary),
      micro: s(size: 10, weight: FontWeight.w600, height: 1.2, color: secondary),
      label: s(size: 14, weight: FontWeight.w600, height: 1.2, tracking: 0.1),
      labelSmall:
          s(size: 12, weight: FontWeight.w600, height: 1.2, tracking: 0.2),
      overline: s(
        size: 11,
        weight: FontWeight.w700,
        height: 1.2,
        tracking: 1.4,
        color: secondary,
      ),
      overlineSmall: s(
        size: 9.5,
        weight: FontWeight.w700,
        height: 1.2,
        tracking: 1.2,
        color: secondary,
      ),
      mono: numeric(size: 14),
      monoSmall: numeric(size: 11.5),
      scientificNameHero: latin(size: 30, weight: FontWeight.w700),
      scientificName: latin(size: 21, weight: FontWeight.w600),
      scientificNameSmall: latin(size: 16, weight: FontWeight.w600),
    );
  }

  @override
  AppTypography copyWith({
    TextStyle? display,
    TextStyle? h1,
    TextStyle? h2,
    TextStyle? h3,
    TextStyle? h4,
    TextStyle? body,
    TextStyle? bodySmall,
    TextStyle? caption,
    TextStyle? micro,
    TextStyle? label,
    TextStyle? labelSmall,
    TextStyle? overline,
    TextStyle? overlineSmall,
    TextStyle? mono,
    TextStyle? monoSmall,
    TextStyle? scientificNameHero,
    TextStyle? scientificName,
    TextStyle? scientificNameSmall,
  }) {
    return AppTypography(
      display: display ?? this.display,
      h1: h1 ?? this.h1,
      h2: h2 ?? this.h2,
      h3: h3 ?? this.h3,
      h4: h4 ?? this.h4,
      body: body ?? this.body,
      bodySmall: bodySmall ?? this.bodySmall,
      caption: caption ?? this.caption,
      micro: micro ?? this.micro,
      label: label ?? this.label,
      labelSmall: labelSmall ?? this.labelSmall,
      overline: overline ?? this.overline,
      overlineSmall: overlineSmall ?? this.overlineSmall,
      mono: mono ?? this.mono,
      monoSmall: monoSmall ?? this.monoSmall,
      scientificNameHero: scientificNameHero ?? this.scientificNameHero,
      scientificName: scientificName ?? this.scientificName,
      scientificNameSmall: scientificNameSmall ?? this.scientificNameSmall,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    TextStyle l(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return AppTypography(
      display: l(display, other.display),
      h1: l(h1, other.h1),
      h2: l(h2, other.h2),
      h3: l(h3, other.h3),
      h4: l(h4, other.h4),
      body: l(body, other.body),
      bodySmall: l(bodySmall, other.bodySmall),
      caption: l(caption, other.caption),
      micro: l(micro, other.micro),
      label: l(label, other.label),
      labelSmall: l(labelSmall, other.labelSmall),
      overline: l(overline, other.overline),
      overlineSmall: l(overlineSmall, other.overlineSmall),
      mono: l(mono, other.mono),
      monoSmall: l(monoSmall, other.monoSmall),
      scientificNameHero: l(scientificNameHero, other.scientificNameHero),
      scientificName: l(scientificName, other.scientificName),
      scientificNameSmall: l(scientificNameSmall, other.scientificNameSmall),
    );
  }
}
