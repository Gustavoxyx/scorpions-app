import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_sizing.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/scorpion_mark.dart';

/// Casca das quatro abas.
///
/// A barra flutua sobre o conteúdo em vez de ocupar uma faixa opaca: as listas
/// de histórico e catálogo ganham altura útil, e a barra continua sempre
/// alcançável pelo polegar.
///
/// Decisão de produto: o botão de identificar NÃO é um item da barra. Ele é a
/// ação principal do aplicativo e ganha destaque próprio — o cartão gigante na
/// Home e, nas outras abas, um botão flutuante logo acima da barra. Rebaixá-lo
/// a um quinto ícone o tornaria equivalente a "Perfil", que é exatamente o que
/// queremos evitar.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const List<_NavItem> _items = <_NavItem>[
    _NavItem(AppStrings.navHome, Icons.home_outlined, Icons.home_rounded),
    _NavItem(AppStrings.navHistory, Icons.history_rounded, Icons.history_rounded),
    _NavItem(AppStrings.navCatalog, Icons.menu_book_outlined,
        Icons.menu_book_rounded),
    _NavItem(AppStrings.navProfile, Icons.person_outline_rounded,
        Icons.person_rounded),
  ];

  /// Altura do degradê que dissolve o conteúdo sob a barra flutuante.
  /// Cobre a barra, a folga inferior e um trecho de transição acima dela.
  static const double _scrimHeight = 132;

  void _onTap(int index) {
    // `initialLocation: true` quando já estamos na aba faz o "voltar ao topo"
    // esperado em apps móveis.
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final bool onHome = shell.currentIndex == 0;

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: <Widget>[
          Positioned.fill(child: shell),

          // Véu de dissolução atrás da barra flutuante.
          //
          // Sem ele, o conteúdo rolava e era cortado por uma aresta dura no
          // topo da barra — parecia bug, não sobreposição. O degradê faz a
          // lista desaparecer no fundo da tela, que é o comportamento esperado
          // de uma barra que flutua sobre o conteúdo.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _scrimHeight,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      c.background.withValues(alpha: 0),
                      c.background.withValues(alpha: 0.92),
                      c.background,
                    ],
                    stops: const <double>[0, 0.55, 1],
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // Acesso rápido à captura fora da Home.
                  AnimatedSlide(
                    offset: onHome ? const Offset(0, 1.6) : Offset.zero,
                    duration: AppMotion.base,
                    curve: AppMotion.emphasized,
                    child: AnimatedOpacity(
                      opacity: onHome ? 0 : 1,
                      duration: AppMotion.fast,
                      child: IgnorePointer(
                        ignoring: onHome,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: _FloatingIdentifyButton(
                            onTap: () => context.push(AppRoutes.capture),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppSizing.maxNavWidth,
                        ),
                        child: _NavBar(
                          items: _items,
                          currentIndex: shell.currentIndex,
                          onTap: _onTap,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<_NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return Container(
      height: AppSizing.navBar,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadii.brXl,
        border: Border.all(color: c.border),
        boxShadow: AppShadows.level2(c.brightness),
      ),
      child: Row(
        children: List<Widget>.generate(items.length, (int i) {
          final bool active = i == currentIndex;
          final _NavItem item = items[i];

          return Expanded(
            child: Pressable(
              onTap: () => onTap(i),
              scale: 0.94,
              semanticLabel: item.label,
              child: SizedBox.expand(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    AnimatedContainer(
                      duration: AppMotion.base,
                      curve: AppMotion.emphasized,
                      padding: EdgeInsets.symmetric(
                        horizontal: active ? AppSpacing.md : AppSpacing.sm,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: active ? c.primarySoft : Colors.transparent,
                        borderRadius: AppRadii.brPill,
                      ),
                      child: Icon(
                        active ? item.activeIcon : item.icon,
                        size: AppSizing.iconLg,
                        color: active ? c.primary : c.textTertiary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.overlineSmall.copyWith(
                        letterSpacing: 0.6,
                        color: active ? c.primary : c.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _FloatingIdentifyButton extends StatelessWidget {
  const _FloatingIdentifyButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Pressable(
      onTap: onTap,
      scale: 0.95,
      semanticLabel: AppStrings.identifyCta,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: c.primary,
          borderRadius: AppRadii.brPill,
          boxShadow: AppShadows.glow(c.primary),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ScorpionMark(size: 20, color: c.onPrimary),
            const SizedBox(width: AppSpacing.sm),
            Text(
              AppStrings.identifyCta,
              style: context.text.label.copyWith(color: c.onPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
