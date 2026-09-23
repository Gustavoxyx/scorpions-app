import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_sizing.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/feedback_states.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/reveal.dart';
import '../../core/widgets/stat_value.dart';
import '../../core/widgets/species_card.dart';
import '../../data/models/species.dart';
import '../../state/catalog_controller.dart';

/// Aba Catálogo.
///
/// # Por que parece um catálogo, e não uma lista
/// Três detalhes fazem esse trabalho: a contagem de registros em tipografia
/// tabular ("8 espécies"), os filtros por **família** — que é a unidade real de
/// organização taxonômica, não uma categoria inventada — e o nome científico em
/// itálico serifado dominando cada cartão.
///
/// A busca ignora acentos e cobre nome científico, popular, família e região. O
/// repositório já é assíncrono, então trocar o mock pelo Firestore na Fase 7
/// não altera esta tela.
class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final CatalogController catalog = context.watch<CatalogController>();

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.maxContentWidth),
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    AppSpacing.lg,
                    AppSpacing.screenGutter,
                    AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  AppStrings.catalogTitle,
                                  style: context.text.h1,
                                ),
                                const SizedBox(height: AppSpacing.xxs),
                                Text(
                                  AppStrings.catalogSubtitle,
                                  style: context.text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          _RecordCount(count: catalog.results.length),
                        ],
                      ),
                      AppSpacing.gapLg,
                      _SearchBar(
                        controller: _search,
                        onChanged: catalog.search,
                        onClear: () {
                          _search.clear();
                          catalog.clearSearch();
                        },
                      ),
                    ],
                  ),
                ),
                _FamilyFilter(
                  families: catalog.families,
                  selected: catalog.family,
                  onToggle: catalog.toggleFamily,
                ),
                Expanded(child: _body(context, catalog)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, CatalogController catalog) {
    if (catalog.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (catalog.hasError && catalog.results.isEmpty) {
      return ErrorState(
        title: 'Catálogo indisponível',
        message: catalog.errorMessage!,
        onRetry: catalog.load,
      );
    }
    if (catalog.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: AppStrings.catalogEmptyTitle,
        message: AppStrings.catalogEmptyBody,
        actionLabel: catalog.isFiltered ? 'Limpar filtros' : null,
        onAction: catalog.isFiltered
            ? () {
                _search.clear();
                catalog.clearFilters();
              }
            : null,
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.xs,
        AppSpacing.screenGutter,
        AppSpacing.bottomNavClearance,
      ),
      itemCount: catalog.results.length,
      separatorBuilder: (BuildContext context, int index) => AppSpacing.gapMd,
      itemBuilder: (BuildContext context, int index) {
        final Species species = catalog.results[index];
        return Reveal(
          // Só os primeiros itens entram escalonados: aplicar atraso a uma
          // lista inteira faria o rodapé aparecer depois de o usuário já ter
          // rolado até lá.
          delay: Duration(milliseconds: 35 * (index > 6 ? 6 : index)),
          child: SpeciesCard(
            species: species,
            onTap: () => context.push(
              AppRoutes.species(species.id),
              extra: species,
            ),
          ),
        );
      },
    );
  }
}

/// Contagem de registros em tipografia tabular — linguagem de acervo.
class _RecordCount extends StatelessWidget {
  const _RecordCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return StatValue(
      value: '$count',
      label: count == 1 ? 'espécie' : 'espécies',
      tint: context.colors.primary,
      alignment: CrossAxisAlignment.end,
      compact: true,
    );
  }
}

/// Filtro por família taxonômica.
///
/// Família é a unidade que um pesquisador usa para navegar um acervo — e, no
/// caso dos escorpiões brasileiros, separa justamente os Buthidae (que
/// concentram as espécies de importância médica) dos demais.
class _FamilyFilter extends StatelessWidget {
  const _FamilyFilter({
    required this.families,
    required this.selected,
    required this.onToggle,
  });

  final List<String> families;
  final String? selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    if (families.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: AppSizing.minTouchTarget,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
        ),
        itemCount: families.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: AppSpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          final String family = families[index];
          return _FamilyChip(
            label: family,
            active: family == selected,
            onTap: () => onToggle(family),
          );
        },
      ),
    );
  }
}

class _FamilyChip extends StatelessWidget {
  const _FamilyChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return Pressable(
      onTap: onTap,
      scale: 0.95,
      semanticLabel: active ? 'Filtro $label ativo' : 'Filtrar por $label',
      child: Center(
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: active ? c.primary : c.surface,
            borderRadius: AppRadii.brPill,
            border: Border.all(color: active ? c.primary : c.border),
          ),
          child: Text(
            label,
            style: context.text.labelSmall.copyWith(
              color: active ? c.onPrimary : c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: AppRadii.brMd,
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.search_rounded,
            size: AppSizing.iconMd,
            color: c.textTertiary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: context.text.body.copyWith(color: c.textPrimary),
              cursorColor: c.primary,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: AppStrings.catalogSearchHint,
                hintStyle: context.text.body.copyWith(color: c.textTertiary),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: AppSpacing.md),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (BuildContext context, TextEditingValue value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return Pressable(
                onTap: onClear,
                semanticLabel: 'Limpar busca',
                child: Icon(
                  Icons.close_rounded,
                  size: AppSizing.iconMd,
                  color: c.textTertiary,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
