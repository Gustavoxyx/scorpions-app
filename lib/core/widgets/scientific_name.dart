import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Escalas de exibição do binômio latino.
enum ScientificNameScale {
  /// Herói da tela de resultado — o momento da descoberta.
  hero,

  /// Cabeçalho da ficha da espécie.
  large,

  /// Título de card e de linha de lista.
  medium,

  /// Metadado dentro de uma linha densa.
  small,
}

/// Nome científico da espécie (brief §8).
///
/// Existe como componente — e não como um `Text` com itálico — porque o binômio
/// latino é o elemento de identidade do produto. Ele carrega três convenções
/// taxonômicas que precisam valer em **todas** as telas:
///
/// 1. **Itálico serifado.** É como a literatura científica escreve desde Lineu.
/// 2. **Gênero abreviável.** Em espaço apertado, *Tityus serrulatus* vira
///    *T. serrulatus* — abreviação correta, não corte com reticências.
/// 3. **Leitura acessível.** Um leitor de tela anuncia "nome científico" antes
///    do nome, para que o itálico não seja a única pista do que aquilo é.
class ScientificName extends StatelessWidget {
  const ScientificName(
    this.name, {
    super.key,
    this.scale = ScientificNameScale.medium,
    this.color,
    this.abbreviateGenus = false,
    this.maxLines = 1,
    this.textAlign,
  });

  final String name;
  final ScientificNameScale scale;
  final Color? color;

  /// Abrevia o gênero (*Tityus serrulatus* → *T. serrulatus*).
  final bool abbreviateGenus;

  final int maxLines;
  final TextAlign? textAlign;

  /// Aplica a abreviação taxonômica do gênero.
  static String abbreviate(String fullName) {
    final List<String> parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length < 2 || parts.first.length < 2) return fullName;
    return '${parts.first[0]}. ${parts.sublist(1).join(' ')}';
  }

  @override
  Widget build(BuildContext context) {
    final String display = abbreviateGenus ? abbreviate(name) : name;

    final TextStyle base = switch (scale) {
      ScientificNameScale.hero => context.text.scientificNameHero,
      ScientificNameScale.large => context.text.scientificName,
      ScientificNameScale.medium => context.text.scientificNameSmall,
      ScientificNameScale.small => context.text.scientificNameSmall
          .copyWith(fontSize: context.text.bodySmall.fontSize),
    };

    return Semantics(
      label: 'Nome científico: $name',
      excludeSemantics: true,
      child: Text(
        display,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: color == null ? base : base.copyWith(color: color),
      ),
    );
  }
}

/// Nome científico com o nome popular abaixo.
///
/// O par aparece junto em quase toda tela; agrupá-lo garante que o espaçamento
/// entre os dois seja sempre o mesmo.
class SpeciesNamePair extends StatelessWidget {
  const SpeciesNamePair({
    super.key,
    required this.scientificName,
    required this.commonName,
    this.scale = ScientificNameScale.medium,
    this.alignment = CrossAxisAlignment.start,
    this.scientificColor,
    this.commonColor,
  });

  final String scientificName;
  final String commonName;
  final ScientificNameScale scale;
  final CrossAxisAlignment alignment;
  final Color? scientificColor;
  final Color? commonColor;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final bool centered = alignment == CrossAxisAlignment.center;

    return Column(
      crossAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ScientificName(
          scientificName,
          scale: scale,
          color: scientificColor,
          textAlign: centered ? TextAlign.center : null,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          commonName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: centered ? TextAlign.center : null,
          style: context.text.bodySmall
              .copyWith(color: commonColor ?? c.textSecondary),
        ),
      ],
    );
  }
}
