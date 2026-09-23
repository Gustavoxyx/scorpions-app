import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/reveal.dart';
import '../../core/widgets/scorpion_mark.dart';
import '../../state/auth_controller.dart';
import 'widgets/auth_error_banner.dart';
import 'widgets/social_login_placeholder.dart';

/// Tela de acesso.
///
/// Não conhece Firebase: fala com [AuthController], que fala com o repositório.
/// Quando a Fase 3 conectar o Firebase Authentication, esta tela não muda uma
/// linha — só a implementação injetada em `app.dart`.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await context.read<AuthController>().signIn(
          email: _email.text.trim(),
          password: _password.text,
        );
    // A navegação acontece pelo guarda do roteador quando o estado muda.
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();
    final AppColors c = context.colors;

    return AppScaffold(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: Reveal.stagger(<Widget>[
            SizedBox(height: context.screenHeight * 0.04),
            const Center(child: ScorpionMark(size: 64, glow: 0.5)),
            AppSpacing.gapXxl,
            Text(
              AppStrings.signInTitle,
              textAlign: TextAlign.center,
              style: context.text.display,
            ),
            AppSpacing.gapSm,
            Text(
              AppStrings.signInSubtitle,
              textAlign: TextAlign.center,
              style: context.text.bodySmall,
            ),
            AppSpacing.gapXxxl,
            if (auth.errorMessage != null) ...<Widget>[
              AuthErrorBanner(message: auth.errorMessage!),
              AppSpacing.gapLg,
            ],
            AppTextField(
              label: AppStrings.fieldEmail,
              controller: _email,
              hint: 'voce@exemplo.com',
              icon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const <String>[AutofillHints.email],
              validator: Validators.email,
              onChanged: (_) => auth.clearError(),
            ),
            AppSpacing.gapLg,
            AppTextField(
              label: AppStrings.fieldPassword,
              controller: _password,
              hint: '••••••••',
              icon: Icons.lock_outline_rounded,
              obscure: true,
              textInputAction: TextInputAction.done,
              autofillHints: const <String>[AutofillHints.password],
              validator: (String? v) => Validators.required(
                v,
                field: AppStrings.fieldPassword,
              ),
              onChanged: (_) => auth.clearError(),
              onSubmitted: (_) => _submit(),
            ),
            AppSpacing.gapSm,
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                label: AppStrings.forgotPassword,
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.small,
                expand: false,
                onPressed: () => context.push(AppRoutes.forgotPassword),
              ),
            ),
            AppSpacing.gapXl,
            AppButton(
              label: AppStrings.signIn,
              onPressed: _submit,
              loading: auth.isBusy,
              glow: true,
            ),
            AppSpacing.gapXxl,
            const SocialLoginPlaceholder(),
            AppSpacing.gapXxl,
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  AppStrings.noAccount,
                  style: context.text.bodySmall.copyWith(color: c.textTertiary),
                ),
                AppButton(
                  label: AppStrings.signUp,
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.small,
                  expand: false,
                  onPressed: () => context.push(AppRoutes.register),
                ),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}
