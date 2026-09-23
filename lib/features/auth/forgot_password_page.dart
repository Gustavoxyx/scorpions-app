import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/feedback_states.dart';
import '../../state/auth_controller.dart';

/// Recuperação de acesso.
///
/// A mensagem de sucesso é deliberadamente neutra ("se existir uma conta"):
/// confirmar a existência de um e-mail cadastrado é vazamento de informação.
/// A regra vale desde o protótipo para não ser esquecida na Fase 3.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final bool ok =
        await context.read<AuthController>().sendPasswordReset(_email.text.trim());
    if (!mounted) return;
    if (ok) setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();

    return AppScaffold(
      title: AppStrings.forgotPasswordTitle,
      showBack: true,
      child: _sent ? _confirmation(context) : _form(context, auth),
    );
  }

  Widget _form(BuildContext context, AuthController auth) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(AppStrings.forgotPasswordBody, style: context.text.body),
          AppSpacing.gapXxl,
          AppTextField(
            label: AppStrings.fieldEmail,
            controller: _email,
            hint: 'voce@exemplo.com',
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            validator: Validators.email,
            onSubmitted: (_) => _submit(),
          ),
          AppSpacing.gapXl,
          AppButton(
            label: AppStrings.forgotPasswordAction,
            onPressed: _submit,
            loading: auth.isBusy,
          ),
        ],
      ),
    );
  }

  Widget _confirmation(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppSpacing.gapXxl,
        Icon(
          Icons.mark_email_read_outlined,
          size: 44,
          color: context.colors.primary,
        ),
        AppSpacing.gapXl,
        Text('Verifique sua caixa de entrada', style: context.text.h3),
        AppSpacing.gapSm,
        Text(
          'Se existir uma conta associada a ${_email.text.trim()}, o link de '
          'redefinição chegará em instantes.',
          style: context.text.body,
        ),
        AppSpacing.gapXxl,
        const DisclaimerBanner(
          message:
              'Nesta versão de demonstração nenhum e-mail é realmente enviado.',
          icon: Icons.science_outlined,
        ),
        AppSpacing.gapXxl,
        AppButton(
          label: 'Voltar para o login',
          variant: AppButtonVariant.secondary,
          onPressed: () => context.pop(),
        ),
      ],
    );
  }
}
