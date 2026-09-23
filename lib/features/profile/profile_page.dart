import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/list_items.dart';
import '../../core/widgets/reveal.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/widgets/stat_value.dart';
import '../../core/widgets/app_badge.dart';
import '../../data/models/user_role.dart';
import '../../data/models/app_user.dart';
import '../../state/auth_controller.dart';
import '../../state/history_controller.dart';
import 'widgets/sign_out_sheet.dart';
import '../../core/theme/app_sizing.dart';

/// Aba Perfil.
///
/// As estatísticas (identificações, espécies vistas) são derivadas do histórico
/// real em memória, não valores fixos — assim o número muda quando o usuário
/// identifica algo, mesmo nesta fase.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final AppUser? user = context.watch<AuthController>().user;
    final HistoryController history = context.watch<HistoryController>();

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.maxContentWidth),
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenGutter,
                AppSpacing.lg,
                AppSpacing.screenGutter,
                AppSpacing.bottomNavClearance,
              ),
              children: Reveal.stagger(<Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(AppStrings.profileTitle,
                          style: context.text.h1),
                    ),
                  ],
                ),
                AppSpacing.gapXl,
                _ProfileHeader(user: user),
                AppSpacing.gapXl,
                _StatsRow(
                  identifications: history.items.length,
                  species: history.distinctSpeciesCount,
                ),
                AppSpacing.gapXxl,
                AppTileGroup(
                  children: <Widget>[
                    AppNavTile(
                      label: AppStrings.settingsTitle,
                      icon: Icons.settings_outlined,
                      onTap: () => context.push(AppRoutes.settings),
                    ),
                    AppNavTile(
                      label: AppStrings.settingsPrivacy,
                      icon: Icons.privacy_tip_outlined,
                      onTap: () => context.push(AppRoutes.settings),
                    ),
                    AppNavTile(
                      label: AppStrings.settingsAbout,
                      icon: Icons.info_outline_rounded,
                      onTap: () => context.push(AppRoutes.about),
                    ),
                  ],
                ),
                AppSpacing.gapLg,
                AppTileGroup(
                  children: <Widget>[
                    AppNavTile(
                      label: AppStrings.signOut,
                      icon: Icons.logout_rounded,
                      tone: AppNavTileTone.danger,
                      showChevron: false,
                      onTap: () => SignOutSheet.show(context),
                    ),
                  ],
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Container(
      padding: AppSpacing.card,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadii.brLg,
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: <Widget>[
          UserAvatar(user: user, size: 60),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  user?.name ?? 'Visitante',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.h3,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  user?.email ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall,
                ),
                // O papel só aparece quando é diferente do comum: mostrar
                // "Usuário" para todo mundo seria ruído. E é apenas
                // informativo — quem autoriza são as Security Rules.
                if (user != null && user!.role != UserRole.user) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  AppBadge(
                    label: user!.role.label,
                    tone: AppBadgeTone.primary,
                    icon: Icons.verified_user_outlined,
                    dense: true,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.identifications, required this.species});

  final int identifications;
  final int species;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _StatCard(
            value: '$identifications',
            label: AppStrings.profileIdentifications,
            icon: Icons.center_focus_strong_outlined,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _StatCard(
            value: '$species',
            label: AppStrings.profileSpecies,
            icon: Icons.pest_control_outlined,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Container(
      padding: AppSpacing.card,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadii.brLg,
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: AppSizing.iconLg, color: c.primary),
          AppSpacing.gapMd,
          StatValue(
            value: value,
            label: label,
            alignment: CrossAxisAlignment.start,
          ),
        ],
      ),
    );
  }
}
