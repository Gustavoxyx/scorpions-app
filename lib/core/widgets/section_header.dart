import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_sizing.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'pressable.dart';

/// Cabeçalho de seção.
///
/// Caixa alta com tracking largo: a linguagem de etiqueta de coleção
/// científica. É pequeno e discreto de propósito — um cabeçalho de seção
/// organiza, não compete com o conteúdo que anuncia.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  final String title;
  final IconData? icon;

  /// Ação textual à direita ("Ver tudo").
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Widget arbitrário à direita. Ignorado quando há [actionLabel].
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return Row(
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: AppSizing.iconSm, color: c.primary),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: context.text.overline.copyWith(color: c.textTertiary),
          ),
        ),
        if (actionLabel != null && onAction != null)
          Pressable(
            onTap: onAction,
            semanticLabel: actionLabel,
            child: Padding(
              // Folga extra para o alvo de toque cobrir a altura mínima sem
              // afastar visualmente o texto da borda.
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                actionLabel!,
                style: context.text.labelSmall.copyWith(color: c.primary),
              ),
            ),
          )
        else
          ?trailing,
      ],
    );
  }
}
