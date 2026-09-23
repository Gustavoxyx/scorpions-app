import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/confidence_badge.dart';
import '../../../core/widgets/specimen_image.dart';
import '../../../data/models/identification.dart';
import '../../../core/theme/app_sizing.dart';

/// Item do histórico.
///
/// Mostra as quatro informações que importam para reencontrar uma
/// identificação: a foto, a espécie, quando foi e o quanto o sistema confiou.
/// Registros rejeitados aparecem com o mesmo peso dos demais — esconder as
/// respostas "não sei" seria maquiar o comportamento do produto.
class HistoryCard extends StatelessWidget {
  const HistoryCard({
    super.key,
    required this.result,
    this.onTap,
  });

  final IdentificationResult result;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final bool rejected = result.isRejected;
    final double thumb = context.isCompact ? 60 : 68;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      semanticLabel: rejected
          ? 'Identificação sem resultado'
          : result.top.species.scientificName,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: thumb,
            height: thumb,
            child: CapturedPhoto(
              image: result.image,
              borderRadius: AppRadii.brSm,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  rejected
                      ? 'Sem identificação'
                      : result.top.species.scientificName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: rejected
                      ? context.text.h4.copyWith(color: c.textSecondary)
                      : context.text.scientificNameSmall,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  rejected
                      ? result.rejectionReason!.title
                      : result.top.species.commonName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: <Widget>[
                    ConfidenceBadge(
                      level: result.level,
                      score: rejected ? null : result.top.score,
                      compact: true,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        Formatters.date(result.createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.monoSmall.copyWith(
                          color: c.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right_rounded, size: AppSizing.iconLg, color: c.textTertiary),
        ],
      ),
    );
  }
}
