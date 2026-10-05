import 'package:flutter/material.dart';

import '../../data/models/app_user.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'pressable.dart';

/// Avatar do usuário.
///
/// Desenha as iniciais sobre a superfície do tema.
///
/// Não há foto de perfil: `AppUser.avatarUrl` existe e está sempre nulo,
/// porque o aplicativo nunca pede nem envia retrato de usuário. Se um dia
/// pedir, é só preencher o campo — mas isso é decisão de produto e de
/// privacidade, não uma lacuna de implementação.
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
