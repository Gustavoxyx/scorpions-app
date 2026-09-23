import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../state/auth_controller.dart';
import '../../../core/theme/app_sizing.dart';

/// Folha de confirmação de saída.
///
/// Sair da conta é reversível, mas ainda assim confirmamos: é um toque a mais
/// que evita logout acidental e a consequente sensação de "perdi meus dados".
/// A navegação de volta ao login é feita pelo guarda do roteador quando o
/// estado de autenticação muda — a folha não navega por conta própria.
class SignOutSheet {
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) => const _SignOutSheetBody(),
    );
  }
}

class _SignOutSheetBody extends StatelessWidget {
  const _SignOutSheetBody();

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.xl),
        ),
        border: Border.all(color: c.border),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.borderStrong,
                  borderRadius: AppRadii.brPill,
                ),
              ),
              AppSpacing.gapXl,
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: c.errorSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.logout_rounded, color: c.error, size: AppSizing.iconXl),
              ),
              AppSpacing.gapLg,
              Text(AppStrings.signOut, style: context.text.h3),
              AppSpacing.gapSm,
              Text(
                AppStrings.signOutConfirm,
                textAlign: TextAlign.center,
                style: context.text.bodySmall,
              ),
              AppSpacing.gapXl,
              AppButton(
                label: AppStrings.signOut,
                variant: AppButtonVariant.danger,
                onPressed: () {
                  Navigator.of(context).pop();
                  context.read<AuthController>().signOut();
                },
              ),
              AppSpacing.gapSm,
              AppButton(
                label: AppStrings.cancel,
                variant: AppButtonVariant.ghost,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
