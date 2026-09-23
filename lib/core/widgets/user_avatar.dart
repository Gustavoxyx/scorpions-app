import 'package:flutter/material.dart';

import '../../data/models/app_user.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'pressable.dart';

/// Avatar do usuário.
///
/// Sem foto (Fase 1), desenha as iniciais sobre a superfície do tema. Quando o
/// Storage entrar na Fase 3, basta preencher `AppUser.avatarUrl`.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.user,
    this.size = 44,
    this.onTap,
  });

  final AppUser? user;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    final Widget content = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.surfaceVariant,
        border: Border.all(color: c.primary.withValues(alpha: 0.45)),
      ),
      alignment: Alignment.center,
      child: user == null
          ? Icon(
              Icons.person_outline_rounded,
              size: size * 0.5,
              color: c.textTertiary,
            )
          : Text(
              user!.initials,
              style: context.text.label.copyWith(
                fontSize: size * 0.34,
                color: c.primary,
              ),
            ),
    );

    if (onTap == null) return content;
    return Pressable(
      onTap: onTap,
      scale: 0.92,
      semanticLabel: 'Abrir perfil',
      child: content,
    );
  }
}
