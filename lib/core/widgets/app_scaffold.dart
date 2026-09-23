import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';

/// Estrutura de tela padrão.
///
/// Resolve de uma vez, e para todas as telas: área segura, largura máxima em
/// tablets, gutter horizontal, folga para a barra inferior e um cabeçalho com
/// botão de voltar consistente. É o que evita que cada tela reinvente o próprio
/// `Scaffold` com paddings ligeiramente diferentes.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.showBack = false,
    this.onBack,
    this.actions,
    this.scrollable = true,
    this.padded = true,
    this.bottomBar,
    this.background,
    this.reserveBottomNav = false,
    this.leading,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final bool showBack;
  final VoidCallback? onBack;
  final List<Widget>? actions;

  /// Envolve o conteúdo em rolagem. Desligue para telas que gerenciam a
  /// própria lista (por exemplo, `ListView.builder`).
  final bool scrollable;

  final bool padded;

  /// Barra fixa no rodapé, fora da rolagem (ações principais).
  final Widget? bottomBar;

  final Color? background;

  /// Reserva espaço inferior quando a tela vive dentro da barra de navegação.
  final bool reserveBottomNav;

  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final bool hasHeader = title != null || showBack || actions != null;

    Widget content = child;

    if (padded) {
      content = Padding(padding: AppSpacing.screen, child: content);
    }

    if (scrollable) {
      content = SingleChildScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: EdgeInsets.only(
          bottom: reserveBottomNav
              ? AppSpacing.bottomNavClearance
              : AppSpacing.xxl,
        ),
        child: content,
      );
    }

    // Em telas largas o conteúdo para de esticar e passa a ser centralizado:
    // linhas de texto muito longas prejudicam a leitura.
    content = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.maxContentWidth),
        child: content,
      ),
    );

    return Scaffold(
      backgroundColor: background ?? c.background,
      body: SafeArea(
        bottom: bottomBar == null,
        child: Column(
          children: <Widget>[
            if (hasHeader)
              _Header(
                title: title,
                subtitle: subtitle,
                showBack: showBack,
                onBack: onBack,
                actions: actions,
                leading: leading,
              ),
            Expanded(child: content),
          ],
        ),
      ),
      bottomNavigationBar: bottomBar == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenGutter,
                  AppSpacing.md,
                  AppSpacing.screenGutter,
                  AppSpacing.md,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(maxWidth: context.maxContentWidth),
                    child: bottomBar,
                  ),
                ),
              ),
            ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    this.title,
    this.subtitle,
    this.showBack = false,
    this.onBack,
    this.actions,
    this.leading,
  });

  final String? title;
  final String? subtitle;
  final bool showBack;
  final VoidCallback? onBack;
  final List<Widget>? actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.md,
        AppSpacing.screenGutter,
        AppSpacing.lg,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: context.maxContentWidth),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              if (showBack) ...<Widget>[
                AppIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Voltar',
                  size: 40,
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: AppSpacing.md),
              ] else if (leading != null) ...<Widget>[
                leading!,
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (title != null)
                      Text(
                        title!,
                        style: context.text.h2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        subtitle!,
                        style: context.text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (actions != null) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                ...actions!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
