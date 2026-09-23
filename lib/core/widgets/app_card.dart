import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'pressable.dart';
import '../theme/app_sizing.dart';

/// Superfície padrão do app.
///
/// Um único componente cobre card estático, card clicável e card em destaque.
/// Isso é o que impede que cada tela invente sua própria borda e seu próprio
/// raio.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = AppSpacing.card,
    this.background,
    this.borderColor,
    this.borderRadius = AppRadii.brLg,
    this.elevated = false,
    this.accent = false,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? background;
  final Color? borderColor;
  final BorderRadius borderRadius;

  /// Aplica sombra de nível 2. Use com parcimônia.
  final bool elevated;

  /// Destaca o card com a borda do acento UV.
  final bool accent;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final Widget surface = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? c.surface,
        borderRadius: borderRadius,
        border: Border.all(
          color: borderColor ?? (accent ? c.primary.withValues(alpha: 0.35) : c.border),
        ),
        boxShadow: elevated ? AppShadows.level2(c.brightness) : null,
      ),
      child: child,
    );

    if (onTap == null) return surface;
    return Pressable(
      onTap: onTap,
      borderRadius: borderRadius,
      semanticLabel: semanticLabel,
      child: surface,
    );
  }
}

/// Bloco de conteúdo com título, usado nas fichas de espécie e nas
/// configurações.
class AppSection extends StatelessWidget {
  const AppSection({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
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
            ?trailing,
          ],
        ),
        AppSpacing.gapMd,
        child,
      ],
    );
  }
}
