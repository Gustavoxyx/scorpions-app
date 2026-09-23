import 'package:flutter/material.dart';

import '../../data/models/species.dart';
import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_sizing.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'app_card.dart';
import 'scientific_name.dart';
import 'specimen_image.dart';

/// Cartão de espécie do catálogo.
///
/// Layout horizontal: a placa à esquerda ancora o olhar, o nome científico
/// domina a hierarquia (itálico serifado, pela convenção taxonômica) e o nome
/// popular vem logo abaixo, seguido da região de ocorrência.
class SpeciesCard extends StatelessWidget {
  const SpeciesCard({
    super.key,
    required this.species,
    this.onTap,
    this.trailing,
  });

  final Species species;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final double plate =
        context.isCompact ? AppSizing.thumbSmall : AppSizing.thumbMedium;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      semanticLabel: '${species.scientificName}, ${species.commonName}',
      child: Row(
        children: <Widget>[
          SizedBox(
            width: plate,
            height: plate,
            child: SpeciesPlate(species: species),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SpeciesNamePair(
                  scientificName: species.scientificName,
                  commonName: species.commonName,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.place_outlined,
                      size: AppSizing.iconXs,
                      color: c.textTertiary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        species.distributionSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.caption.copyWith(
                          color: c.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ] else if (onTap != null)
            Icon(
              Icons.chevron_right_rounded,
              size: AppSizing.iconMd,
              color: c.textTertiary,
            ),
        ],
      ),
    );
  }
}

/// Etiqueta taxonômica compacta: família · gênero · espécie.
///
/// É o elemento que mais aproxima a ficha de uma etiqueta de coleção: três
/// campos, rótulos em caixa alta pequena, valores em itálico serifado.
class TaxonomyStrip extends StatelessWidget {
  const TaxonomyStrip({super.key, required this.species});

  final Species species;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final List<(String, String)> entries = <(String, String)>[
      ('Família', species.family),
      ('Gênero', species.genus),
      ('Espécie', species.specificEpithet),
    ];

    return Container(
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: AppRadii.brSm,
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < entries.length; i++) ...<Widget>[
            if (i > 0)
              Container(
                width: AppSizing.hairline,
                height: 26,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                color: c.border,
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    entries[i].$1.toUpperCase(),
                    style: context.text.overlineSmall
                        .copyWith(color: c.textTertiary),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  ScientificName(
                    entries[i].$2,
                    scale: ScientificNameScale.small,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
