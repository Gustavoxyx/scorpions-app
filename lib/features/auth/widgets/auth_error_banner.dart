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


/// Reserva **sempre** o lugar do banner na lista de filhos do formulário.
///
/// # Por que isto existe
/// `Column` reconcilia os filhos por posição. Enquanto o banner entrava e
/// saía da lista, tudo abaixo dele deslizava duas posições e o Flutter
/// inflava elementos novos no lugar dos antigos — descartando o `State` dos
/// campos de texto e, junto com ele, o `FocusNode` de cada um.
///
/// O efeito para o usuário era este: depois de um login recusado, a primeira
/// tecla digitada na senha chamava `clearError()`, o banner sumia, os campos
/// eram recriados e o foco evaporava. Dava a impressão de campo travado.
///
/// Mantendo um slot de altura zero quando não há erro, o comprimento da lista
/// nunca muda e nada desliza.
class AuthErrorSlot extends StatelessWidget {
  const AuthErrorSlot({super.key, required this.message});

  /// Mensagem atual, ou `null` quando não há erro.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final String? m = message;
    if (m == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AuthErrorBanner(message: m),
    );
  }
}
