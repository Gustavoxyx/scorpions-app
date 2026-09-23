import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'pressable.dart';
import '../theme/app_sizing.dart';

/// Hierarquia visual dos botões. Uma tela nunca deve ter duas ações
/// [AppButtonVariant.primary] competindo entre si.
enum AppButtonVariant { primary, secondary, ghost, danger }

enum AppButtonSize { large, medium, small }

/// Botão padrão do produto.
///
/// Concentra estado de carregamento, ícone, largura, feedback de toque e as
/// quatro variantes. Nenhuma tela declara `ElevatedButton` diretamente.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.large,
    this.icon,
    this.trailingIcon,
    this.expand = true,
    this.loading = false,
    this.glow = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final IconData? trailingIcon;

  /// Ocupa toda a largura disponível.
  final bool expand;

  final bool loading;

  /// Halo ultravioleta. Reservado à ação principal do aplicativo.
  final bool glow;

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final _ButtonStyle style = _resolve(c);
    final double height = switch (size) {
      AppButtonSize.large => 54,
      AppButtonSize.medium => 46,
      AppButtonSize.small => 38,
    };
    final TextStyle textStyle = switch (size) {
      AppButtonSize.small => context.text.labelSmall,
      _ => context.text.label,
    };

    final Widget content = loading
        ? SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(style.foreground),
            ),
          )
        : Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: AppSizing.iconMd, color: style.foreground),
                const SizedBox(width: AppSpacing.sm),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: textStyle.copyWith(color: style.foreground),
                ),
              ),
              if (trailingIcon != null) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                Icon(trailingIcon, size: AppSizing.iconMd, color: style.foreground),
              ],
            ],
          );

    return Pressable(
      onTap: _enabled ? onPressed : null,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.standard,
        height: height,
        width: expand ? double.infinity : null,
        padding: EdgeInsets.symmetric(
          horizontal: size == AppButtonSize.small ? AppSpacing.md : AppSpacing.xl,
        ),
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: AppRadii.brMd,
          border: style.border == null
              ? null
              : Border.all(color: style.border!, width: 1.2),
          boxShadow: glow && _enabled
              ? AppShadows.glow(c.primary, strength: 0.9)
              : null,
        ),
        child: Center(child: content),
      ),
    );
  }

  _ButtonStyle _resolve(AppColors c) {
    if (!_enabled) {
      return _ButtonStyle(
        background: variant == AppButtonVariant.ghost
            ? Colors.transparent
            : c.surfaceSunken,
        foreground: c.textTertiary,
        border: variant == AppButtonVariant.secondary ? c.border : null,
      );
    }
    return switch (variant) {
      AppButtonVariant.primary => _ButtonStyle(
          background: c.primary,
          foreground: c.onPrimary,
        ),
      AppButtonVariant.secondary => _ButtonStyle(
          background: Colors.transparent,
          foreground: c.textPrimary,
          border: c.borderStrong,
        ),
      AppButtonVariant.ghost => _ButtonStyle(
          background: Colors.transparent,
          foreground: c.primary,
        ),
      AppButtonVariant.danger => _ButtonStyle(
          background: c.errorSoft,
          foreground: c.error,
          border: c.error.withValues(alpha: 0.4),
        ),
    };
  }
}

class _ButtonStyle {
  const _ButtonStyle({
    required this.background,
    required this.foreground,
    this.border,
  });

  final Color background;
  final Color foreground;
  final Color? border;
}

/// Botão de ícone circular usado em barras de navegação e sobre a câmera.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 44,
    this.background,
    this.foreground,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final Widget button = Pressable(
      onTap: onPressed,
      scale: 0.92,
      semanticLabel: tooltip,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background ?? c.surfaceVariant,
          shape: BoxShape.circle,
          border: Border.all(color: c.border),
        ),
        child: Icon(icon, size: size * 0.44, color: foreground ?? c.textPrimary),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
