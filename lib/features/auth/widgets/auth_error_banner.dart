import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_sizing.dart';

/// Mensagem de erro dos formulários de autenticação.
///
/// A mensagem já chega traduzida pelo repositório — a tela nunca interpreta
/// código de erro de SDK.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Container(
      padding: AppSpacing.cardCompact,
      decoration: BoxDecoration(
        color: c.errorSoft,
        borderRadius: AppRadii.brSm,
        border: Border.all(color: c.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: AppSizing.iconMd, color: c.error),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: context.text.bodySmall.copyWith(color: c.error),
            ),
          ),
        ],
      ),
    );
  }
}
