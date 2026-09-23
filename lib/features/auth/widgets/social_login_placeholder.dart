import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_sizing.dart';

/// Espaço reservado ao login social.
///
/// Os botões existem desabilitados, com aviso explícito, em vez de simular um
/// fluxo que não existe. Na Fase 3 basta ligar o `onPressed` de cada um ao
/// provedor correspondente do Firebase Authentication.
class SocialLoginPlaceholder extends StatelessWidget {
  const SocialLoginPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Divider(color: c.border)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                AppStrings.socialDivider.toUpperCase(),
                style: context.text.overline.copyWith(color: c.textTertiary),
              ),
            ),
            Expanded(child: Divider(color: c.border)),
          ],
        ),
        AppSpacing.gapLg,
        const Row(
          children: <Widget>[
            _SocialSlot(label: 'Google', icon: Icons.g_mobiledata_rounded),
            SizedBox(width: AppSpacing.md),
            _SocialSlot(label: 'Apple', icon: Icons.apple_rounded),
          ],
        ),
        AppSpacing.gapSm,
        Text(
          AppStrings.socialSoon,
          textAlign: TextAlign.center,
          style: context.text.bodySmall
              .copyWith(color: c.textTertiary),
        ),
      ],
    );
  }
}

class _SocialSlot extends StatelessWidget {
  const _SocialSlot({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Expanded(
      child: Opacity(
        opacity: 0.45,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            borderRadius: AppRadii.brMd,
            border: Border.all(color: c.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: AppSizing.iconLg, color: c.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: context.text.labelSmall.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
