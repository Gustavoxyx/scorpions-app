import 'package:flutter/material.dart';

import '../constants/app_config.dart';
import '../constants/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';
import 'scorpion_mark.dart';
import '../theme/app_sizing.dart';

/// Estado vazio. Toda lista do app usa este componente — nunca uma tela em
/// branco.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.icon,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxxl,
          vertical: AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
                border: Border.all(color: c.border),
              ),
              child: icon == null
                  ? Center(
                      child: ScorpionMark(
                        size: 44,
                        color: c.textTertiary.withValues(alpha: 0.7),
                      ),
                    )
                  : Icon(icon, size: AppSizing.iconHero, color: c.textTertiary),
            ),
            AppSpacing.gapXl,
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.text.h3,
            ),
            AppSpacing.gapSm,
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.text.bodySmall,
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              AppSpacing.gapXl,
              AppButton(
                label: actionLabel!,
                onPressed: onAction,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.medium,
                expand: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Estado de erro recuperável.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.title = 'Algo deu errado',
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline_rounded, size: AppSizing.iconHero, color: c.error),
            AppSpacing.gapLg,
            Text(title, textAlign: TextAlign.center, style: context.text.h3),
            AppSpacing.gapSm,
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.text.bodySmall,
            ),
            if (onRetry != null) ...<Widget>[
              AppSpacing.gapXl,
              AppButton(
                label: AppStrings.tryAgain,
                onPressed: onRetry,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.medium,
                expand: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Selo permanente de dado simulado.
///
/// Enquanto [AppConfig.useMockIdentification] for verdadeiro, todo resultado
/// exibido carrega este selo. É uma exigência de honestidade do produto: o
/// usuário nunca deve confundir demonstração com identificação real.
class MockDataBadge extends StatelessWidget {
  const MockDataBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.useMockIdentification) return const SizedBox.shrink();
    final AppColors c = context.colors;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : AppSpacing.md,
        vertical: compact ? 3 : AppSpacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: c.warningSoft,
        borderRadius: AppRadii.brXs,
        border: Border.all(color: c.secondary.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.science_outlined, size: compact ? 11 : 13, color: c.secondary),
          const SizedBox(width: AppSpacing.xs + 1),
          Text(
            AppStrings.mockBadge,
            style: context.text.overline.copyWith(
              color: c.secondary,
              fontSize: compact ? 9 : 10,
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso de responsabilidade. Aparece sempre que houver conteúdo de saúde.
class DisclaimerBanner extends StatelessWidget {
  const DisclaimerBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.tone = DisclaimerTone.neutral,
  });

  final String message;
  final IconData icon;
  final DisclaimerTone tone;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final Color tint = switch (tone) {
      DisclaimerTone.neutral => c.textSecondary,
      DisclaimerTone.caution => c.secondary,
      DisclaimerTone.critical => c.error,
    };
    final Color background = switch (tone) {
      DisclaimerTone.neutral => c.surfaceSunken,
      DisclaimerTone.caution => c.warningSoft,
      DisclaimerTone.critical => c.errorSoft,
    };

    return Container(
      padding: AppSpacing.cardCompact,
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadii.brSm,
        border: Border.all(color: tint.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: AppSizing.iconMd, color: tint),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: context.text.bodySmall.copyWith(
                color: tone == DisclaimerTone.neutral ? c.textSecondary : tint,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum DisclaimerTone { neutral, caution, critical }
