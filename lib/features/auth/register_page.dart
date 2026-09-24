import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/feedback_states.dart';
import '../../state/auth_controller.dart';
import 'widgets/auth_error_banner.dart';

/// Criação de conta.
///
/// As validações são de interface: dão resposta imediata e evitam uma ida
/// inútil ao servidor. A autoridade sobre unicidade de e-mail e política de
/// senha continua sendo do backend (Fase 3).
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  double _strength = 0;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await context.read<AuthController>().signUp(
          name: _name.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final AuthController auth = context.watch<AuthController>();

    return AppScaffold(
      title: AppStrings.signUpTitle,
      subtitle: AppStrings.signUpSubtitle,
      showBack: true,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AuthErrorSlot(message: auth.errorMessage),
            AppTextField(
              key: const ValueKey<String>('cadastro-nome'),
              label: AppStrings.fieldName,
              controller: _name,
              hint: 'Como devemos chamar você',
              icon: Icons.person_outline_rounded,
              textInputAction: TextInputAction.next,
              autofillHints: const <String>[AutofillHints.name],
              validator: Validators.name,
              onChanged: (_) => auth.clearError(),
            ),
            AppSpacing.gapLg,
            AppTextField(
              key: const ValueKey<String>('cadastro-email'),
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
              key: const ValueKey<String>('cadastro-senha'),
              label: AppStrings.fieldPassword,
              controller: _password,
              hint: 'Mínimo de ${Validators.minPasswordLength} caracteres',
              icon: Icons.lock_outline_rounded,
              obscure: true,
              textInputAction: TextInputAction.next,
              autofillHints: const <String>[AutofillHints.newPassword],
              validator: Validators.password,
              onChanged: (String v) {
                auth.clearError();
                setState(() => _strength = Validators.passwordStrength(v));
              },
            ),
            AppSpacing.gapSm,
            _StrengthBar(value: _strength),
            AppSpacing.gapLg,
            AppTextField(
              key: const ValueKey<String>('cadastro-confirmar'),
              label: AppStrings.fieldPasswordConfirm,
              controller: _confirm,
              hint: 'Repita a senha',
              icon: Icons.lock_reset_rounded,
              obscure: true,
              textInputAction: TextInputAction.done,
              validator: (String? v) =>
                  Validators.passwordConfirmation(v, _password.text),
              onChanged: (_) => auth.clearError(),
              onSubmitted: (_) => _submit(),
            ),
            AppSpacing.gapXl,
            const DisclaimerBanner(
              message:
                  'Nesta versão de demonstração nenhum dado é enviado a um '
                  'servidor: a conta existe apenas na memória do aparelho.',
              icon: Icons.shield_outlined,
            ),
            AppSpacing.gapXl,
            AppButton(
              label: AppStrings.signUp,
              onPressed: _submit,
              loading: auth.isBusy,
              glow: true,
            ),
            AppSpacing.gapXxl,
          ],
        ),
      ),
    );
  }
}

/// Indicador de força da senha. É orientação, não bloqueio.
class _StrengthBar extends StatelessWidget {
  const _StrengthBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final Color tint = value >= 0.8
        ? c.primary
        : value >= 0.5
            ? c.secondary
            : c.error;
    final String label = value == 0
        ? ''
        : value >= 0.8
            ? 'Senha forte'
            : value >= 0.5
                ? 'Senha razoável'
                : 'Senha fraca';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: AppRadii.brPill,
          child: SizedBox(
            height: 4,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ColoredBox(color: c.surfaceSunken),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedFractionallySizedBox(
                    duration: AppMotion.base,
                    curve: AppMotion.standard,
                    widthFactor: value,
                    heightFactor: 1,
                    child: ColoredBox(color: tint),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (label.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: context.text.caption.copyWith(color: tint),
          ),
        ],
      ],
    );
  }
}
