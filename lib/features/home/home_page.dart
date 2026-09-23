import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_sizing.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/reveal.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/models/app_user.dart';
import '../../data/models/identification.dart';
import '../../state/auth_controller.dart';
import '../../state/history_controller.dart';
import '../../state/identification_controller.dart';
import '../history/widgets/history_card.dart';
import 'widgets/identify_hero_card.dart';

/// Tela inicial.
///
/// # Hierarquia
/// De cima para baixo: quem é você → **o que fazer agora** → para onde mais ir
/// → como melhorar o resultado → o que você já descobriu. O cartão de
/// identificar é o único elemento com peso de cor cheia; tudo abaixo dele é
/// deliberadamente mais leve (brief §11).
///
/// # Por que os atalhos são três, e não quatro
/// A Fase 1 tinha um atalho "Perfil" — que já é item da barra inferior.
/// Repetir o mesmo destino duas vezes na mesma tela gasta atenção sem oferecer
/// nada em troca.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  void _startIdentification(BuildContext context) {
    // Limpa qualquer resultado anterior para que a análise não herde estado de
    // uma sessão passada.
    context.read<IdentificationController>().reset();
    context.push(AppRoutes.capture);
  }

  void _openResult(BuildContext context, IdentificationResult result) {
    context.read<IdentificationController>().showExisting(result);
    context.push(result.isRejected ? AppRoutes.unidentified : AppRoutes.result);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final AuthController auth = context.watch<AuthController>();
    final HistoryController history = context.watch<HistoryController>();
    final List<IdentificationResult> recent =
        history.items.take(2).toList(growable: false);

    // Blocos de conteúdo. A entrada escalonada é aplicada só a eles — nunca aos
    // espaçadores. Na Fase 1 os espaçadores contavam como itens e o atraso
    // acumulado deixava a Home visualmente vazia por mais de um segundo.
    final List<Widget> blocks = <Widget>[
      _Greeting(user: auth.user, onProfile: () => context.go(AppRoutes.profile)),
      IdentifyHeroCard(onIdentify: () => _startIdentification(context)),
      _ShortcutRow(historyCount: history.items.length),
      const _LearnBlock(),
      if (recent.isNotEmpty)
        _RecentBlock(
          items: recent,
          onSeeAll: () => context.go(AppRoutes.history),
          onOpen: (IdentificationResult r) => _openResult(context, r),
        ),
    ];

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.maxContentWidth),
            child: RefreshIndicator(
              onRefresh: history.refresh,
              color: c.primary,
              backgroundColor: c.surface,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenGutter,
                  AppSpacing.lg,
                  AppSpacing.screenGutter,
                  AppSpacing.bottomNavClearance,
                ),
                itemCount: blocks.length,
                separatorBuilder: (BuildContext context, int i) => SizedBox(
                  // O cabeçalho gruda no cartão principal; as demais seções
                  // respiram mais.
                  height: i == 0 ? AppSpacing.xxl : AppSpacing.xxxl,
                ),
                itemBuilder: (BuildContext context, int i) => Reveal(
                  delay: HomeEntrance.delayAt(i),
                  child: blocks[i],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Escalonamento da entrada da Home.
///
/// O teto é o ponto importante: a partir do quinto bloco o atraso para de
/// crescer. Sem teto, o último item de uma lista longa só termina de aparecer
/// depois de o usuário já ter começado a rolar.
abstract final class HomeEntrance {
  static const Duration _step = Duration(milliseconds: 55);
  static const int _maxSteps = 4;

  static Duration delayAt(int index) =>
      _step * (index > _maxSteps ? _maxSteps : index);
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.user, required this.onProfile});

  final AppUser? user;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final String name = user?.firstName ?? '';
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                Formatters.greeting(DateTime.now()),
                style: context.text.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                name.isEmpty ? 'Bem-vindo' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.h2,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        UserAvatar(user: user, onTap: onProfile),
      ],
    );
  }
}

/// Três atalhos numa única linha.
///
/// Linha em vez de grade 2×2: ocupa metade da altura e comunica que são
/// destinos secundários, não ações.
class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.historyCount});

  final int historyCount;

  @override
  Widget build(BuildContext context) {
    final List<Widget> items = <Widget>[
      _ShortcutTile(
        label: AppStrings.navHistory,
        icon: Icons.history_rounded,
        badge: historyCount > 0 ? '$historyCount' : null,
        onTap: () => context.go(AppRoutes.history),
      ),
      _ShortcutTile(
        label: AppStrings.navCatalog,
        icon: Icons.menu_book_outlined,
        onTap: () => context.go(AppRoutes.catalog),
      ),
      _ShortcutTile(
        label: 'Informações',
        icon: Icons.info_outline_rounded,
        onTap: () => context.push(AppRoutes.about),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(title: AppStrings.homeShortcuts),
        AppSpacing.gapMd,
        // `IntrinsicHeight` iguala a altura dos três cartões sem que nenhum
        // precise de altura fixa. Não usar `CrossAxisAlignment.stretch` aqui:
        // dentro de uma lista rolável a Row não tem altura definida, e o
        // stretch quebra o layout silenciosamente em build de release.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < items.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: AppSpacing.md),
                Expanded(child: items[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({
    required this.label,
    required this.icon,
    required this.onTap,
    this.badge,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return Pressable(
      onTap: onTap,
      semanticLabel: badge == null ? label : '$label, $badge itens',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: AppRadii.brLg,
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: AppSizing.iconLg, color: c.primary),
                if (badge != null) ...<Widget>[
                  const Spacer(),
                  Text(
                    badge!,
                    style:
                        context.text.monoSmall.copyWith(color: c.textTertiary),
                  ),
                ],
              ],
            ),
            AppSpacing.gapLg,
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall.copyWith(color: c.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _LearnBlock extends StatelessWidget {
  const _LearnBlock();

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(title: AppStrings.homeLearn),
        AppSpacing.gapMd,
        AppCard(
          onTap: () => context.push(AppRoutes.photoTips),
          semanticLabel: AppStrings.photoTipsTitle,
          child: Row(
            children: <Widget>[
              Container(
                width: AppSizing.iconTileMedium,
                height: AppSizing.iconTileMedium,
                decoration: BoxDecoration(
                  color: c.secondarySoft,
                  borderRadius: AppRadii.brSm,
                ),
                child: Icon(
                  Icons.center_focus_strong_outlined,
                  size: AppSizing.iconLg,
                  color: c.secondary,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(AppStrings.photoTipsTitle, style: context.text.h4),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      AppStrings.photoTipsSubtitle,
                      style: context.text.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                Icons.chevron_right_rounded,
                size: AppSizing.iconMd,
                color: c.textTertiary,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentBlock extends StatelessWidget {
  const _RecentBlock({
    required this.items,
    required this.onSeeAll,
    required this.onOpen,
  });

  final List<IdentificationResult> items;
  final VoidCallback onSeeAll;
  final ValueChanged<IdentificationResult> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: AppStrings.homeRecent,
          actionLabel: AppStrings.seeAll,
          onAction: onSeeAll,
        ),
        AppSpacing.gapMd,
        for (int i = 0; i < items.length; i++) ...<Widget>[
          if (i > 0) AppSpacing.gapMd,
          HistoryCard(result: items[i], onTap: () => onOpen(items[i])),
        ],
      ],
    );
  }
}
