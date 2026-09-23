import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_sizing.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'pressable.dart';

/// Linha "rótulo → valor" das fichas de espécie e do perfil.
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.italicValue = false,
    this.icon,
  });

  final String label;
  final String value;

  /// Nomes científicos são exibidos em itálico.
  final bool italicValue;

  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final TextStyle valueStyle = italicValue
        ? context.text.scientificNameSmall
        : context.text.h4;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: AppSizing.iconSm, color: c.textTertiary),
            const SizedBox(width: AppSpacing.sm),
          ],
          SizedBox(
            width: context.isCompact ? 96 : 116,
            child: Text(
              label,
              style: context.text.bodySmall.copyWith(color: c.textTertiary),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(value, style: valueStyle)),
        ],
      ),
    );
  }
}

/// Item de navegação de lista (perfil, configurações).
class AppNavTile extends StatelessWidget {
  const AppNavTile({
    super.key,
    required this.label,
    this.icon,
    this.value,
    this.onTap,
    this.tone = AppNavTileTone.normal,
    this.showChevron = true,
  });

  final String label;
  final IconData? icon;

  /// Texto secundário à direita (idioma escolhido, versão, etc.).
  final String? value;

  final VoidCallback? onTap;
  final AppNavTileTone tone;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final Color tint = switch (tone) {
      AppNavTileTone.normal => c.textPrimary,
      AppNavTileTone.muted => c.textSecondary,
      AppNavTileTone.danger => c.error,
    };

    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        color: Colors.transparent,
        child: Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(
                icon,
                size: AppSizing.iconMd,
                color: tone == AppNavTileTone.danger
                    ? c.error
                    : c.textSecondary,
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.h4.copyWith(color: tint),
              ),
            ),
            // O valor precisa ser flexível: nada impede que ele seja longo (um
            // idioma, um estado, uma data). Sem isto a linha estoura em telas
            // estreitas ou com a fonte ampliada por acessibilidade — foi
            // exatamente o que o teste de responsividade pegou em 320dp.
            if (value != null) ...<Widget>[
              const SizedBox(width: AppSpacing.md),
              Flexible(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: context.text.bodySmall.copyWith(color: c.textTertiary),
                ),
              ),
            ],
            if (showChevron && onTap != null) ...<Widget>[
              const SizedBox(width: AppSpacing.sm),
              Icon(
                Icons.chevron_right_rounded,
                size: AppSizing.iconMd,
                color: c.textTertiary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum AppNavTileTone { normal, muted, danger }

/// Item com interruptor.
class AppSwitchTile extends StatelessWidget {
  const AppSwitchTile({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
    this.icon,
    this.enabled = true,
  });

  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: AppSizing.iconMd, color: c.textSecondary),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: context.text.h4.copyWith(
                    color: enabled ? c.textPrimary : c.textTertiary,
                  ),
                ),
                if (description != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(description!, style: context.text.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

/// Agrupa itens de lista numa superfície única com divisores internos.
class AppTileGroup extends StatelessWidget {
  const AppTileGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadii.brLg,
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: c.border, indent: AppSpacing.lg),
            children[i],
          ],
        ],
      ),
    );
  }
}
