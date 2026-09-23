import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Campo de texto do produto.
///
/// Encapsula rótulo, ícone, erro, alternância de senha e foco. As telas de
/// login e cadastro não sabem como um campo é desenhado — só o que ele pede.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.icon,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onSubmitted,
    this.onChanged,
    this.autofillHints,
    this.enabled = true,
    this.maxLength,
    this.helper,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final IconData? icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final List<String>? autofillHints;
  final bool enabled;
  final int? maxLength;

  /// Texto auxiliar permanente, abaixo do campo.
  final String? helper;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  final FocusNode _focus = FocusNode();
  bool _obscured = true;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return FormField<String>(
      initialValue: widget.controller.text,
      validator: (_) => widget.validator?.call(widget.controller.text),
      builder: (FormFieldState<String> field) {
        final bool hasError = field.hasError;
        final Color borderColor = hasError
            ? c.error
            : _focused
                ? c.primary
                : c.border;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.label.toUpperCase(),
              style: context.text.overline.copyWith(
                color: hasError ? c.error : c.textTertiary,
              ),
            ),
            AppSpacing.gapSm,
            AnimatedContainer(
              duration: Motion.fast,
              curve: Motion.standard,
              decoration: BoxDecoration(
                color: widget.enabled ? c.surfaceSunken : c.surface,
                borderRadius: AppRadii.brMd,
                border: Border.all(color: borderColor, width: _focused ? 1.6 : 1),
              ),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: <Widget>[
                  if (widget.icon != null) ...<Widget>[
                    Icon(
                      widget.icon,
                      size: 19,
                      color: _focused ? c.primary : c.textTertiary,
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focus,
                      enabled: widget.enabled,
                      obscureText: widget.obscure && _obscured,
                      keyboardType: widget.keyboardType,
                      textInputAction: widget.textInputAction,
                      autofillHints: widget.autofillHints,
                      maxLength: widget.maxLength,
                      style: context.text.body.copyWith(color: c.textPrimary),
                      cursorColor: c.primary,
                      inputFormatters: widget.keyboardType ==
                              TextInputType.emailAddress
                          ? <TextInputFormatter>[
                              FilteringTextInputFormatter.deny(RegExp(r'\s')),
                            ]
                          : null,
                      decoration: InputDecoration(
                        isDense: true,
                        counterText: '',
                        border: InputBorder.none,
                        hintText: widget.hint,
                        hintStyle:
                            context.text.body.copyWith(color: c.textTertiary),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.lg,
                        ),
                      ),
                      onChanged: (String value) {
                        field.didChange(value);
                        widget.onChanged?.call(value);
                      },
                      onSubmitted: widget.onSubmitted,
                    ),
                  ),
                  if (widget.obscure)
                    GestureDetector(
                      onTap: () => setState(() => _obscured = !_obscured),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.sm),
                        child: Icon(
                          _obscured
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 19,
                          color: c.textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (hasError || widget.helper != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs + 2),
              Text(
                hasError ? field.errorText! : widget.helper!,
                style: context.text.bodySmall.copyWith(
                  color: hasError ? c.error : c.textTertiary,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
