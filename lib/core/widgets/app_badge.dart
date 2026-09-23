import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_sizing.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Tom semântico de uma etiqueta.
enum AppBadgeTone {
  /// Metadado neutro: contagem, categoria, região.
  neutral,

  /// Marca: categoria do produto, destaque positivo.
  primary,

  /// Acento orgânico: classificação, agrupamento.
  secondary,

  success,
  warning,
  error,

  /// Sobre fotografia ou visor de câmera.
  onMedia,
}

/// Etiqueta compacta (pill).
///
/// A auditoria da Fase 1 encontrou este mesmo `Container + padding + raio pill`
/// remontado à mão **12 vezes em 9 arquivos** — cada um com padding e tamanho
/// de fonte ligeiramente diferentes. Este componente é a única fonte de verdade.
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.tone = AppBadgeTone.neutral,
    this.icon,
    this.trailing,
    this.dense = false,
    this.outlined = true,
  });

  final String label;
  final AppBadgeTone tone;
  final IconData? icon;

  /// Conteúdo à direita do rótulo — normalmente um número.
  final Widget? trailing;

  /// Versão reduzida, para dentro de linhas de lista.
  final bool dense;

  /// Contorno sutil. Desligue quando o fundo já isolar a etiqueta.
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final (Color fg, Color bg) = _resolve(c);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.sm : AppSpacing.md,
        vertical: dense ? AppSpacing.xxs + 1 : AppSpacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadii.brPill,
        border: outlined
            ? Border.all(color: fg.withValues(alpha: 0.32))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(
              icon,
              size: dense ? AppSizing.iconXs : AppSizing.iconSm,
              color: fg,
            ),
            const SizedBox(width: AppSpacing.xs + 1),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (dense ? context.text.overlineSmall : context.text.overline)
                  .copyWith(color: fg),
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: AppSpacing.xs + 2),
            DefaultTextStyle.merge(
              style: (dense ? context.text.monoSmall : context.text.mono)
                  .copyWith(color: fg),
              child: trailing!,
            ),
          ],
        ],
      ),
    );
  }

  (Color, Color) _resolve(AppColors c) => switch (tone) {
        AppBadgeTone.neutral => (c.textSecondary, c.surfaceSunken),
        AppBadgeTone.primary => (c.primary, c.primarySoft),
        AppBadgeTone.secondary => (c.secondary, c.secondarySoft),
        AppBadgeTone.success => (c.success, c.successSoft),
        AppBadgeTone.warning => (c.warning, c.warningSoft),
        AppBadgeTone.error => (c.error, c.errorSoft),
        AppBadgeTone.onMedia => (c.onMedia, c.scrim),
      };
}
