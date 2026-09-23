import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_sizing.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/feedback_states.dart';
import '../../core/widgets/list_items.dart';
import '../../core/widgets/reveal.dart';
import '../../core/widgets/scientific_name.dart';
import '../../core/widgets/species_card.dart';
import '../../core/widgets/specimen_image.dart';
import '../../data/models/species.dart';
import '../../data/repositories/species_repository.dart';
import 'widgets/medical_relevance_panel.dart';
import 'widgets/model_3d_slot.dart';
import 'widgets/morphology_section.dart';

/// Ficha completa da espécie.
///
/// Recebe a espécie já carregada quando vem do resultado ou do catálogo; se
/// abrir por id (link direto, histórico antigo), busca no repositório. As duas
/// portas de entrada convergem para o mesmo conteúdo.
class SpeciesDetailPage extends StatefulWidget {
  const SpeciesDetailPage({
    super.key,
    required this.speciesId,
    this.preloaded,
  });

  final String speciesId;
  final Species? preloaded;

  @override
  State<SpeciesDetailPage> createState() => _SpeciesDetailPageState();
}

class _SpeciesDetailPageState extends State<SpeciesDetailPage> {
  Species? _species;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    if (widget.preloaded != null) {
      _species = widget.preloaded;
      _loading = false;
      return;
    }
    final Species? found =
        await context.read<SpeciesRepository>().findById(widget.speciesId);
    if (!mounted) return;
    setState(() {
      _species = found;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    if (_loading) {
      return Scaffold(
        backgroundColor: c.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final Species? species = _species;
    if (species == null) {
      return Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: ErrorState(
            title: 'Espécie não encontrada',
            message: 'Este registro não existe no catálogo atual.',
            onRetry: () => Navigator.of(context).maybePop(),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: <Widget>[
          _SpeciesAppBar(species: species),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.xl,
              AppSpacing.screenGutter,
              AppSpacing.xxxl,
            ),
            sliver: SliverList.list(
              children: Reveal.stagger(<Widget>[
                Text(species.summary, style: context.text.body),
                AppSpacing.gapXxl,

                // Identificação.
                AppSection(
                  title: AppStrings.speciesIdentification,
                  icon: Icons.fingerprint_rounded,
                  child: Column(
                    children: <Widget>[
                      TaxonomyStrip(species: species),
                      AppSpacing.gapSm,
                      InfoRow(
                        label: 'Nome científico',
                        value: species.scientificName,
                        italicValue: true,
                      ),
                      InfoRow(label: 'Nome comum', value: species.commonName),
                    ],
                  ),
                ),
                AppSpacing.gapXxl,

                // Características.
                AppSection(
                  title: AppStrings.speciesTraits,
                  icon: Icons.straighten_rounded,
                  child: AppCard(
                    child: Column(
                      children: <Widget>[
                        InfoRow(label: 'Tamanho', value: species.sizeRange),
                        _divider(context),
                        InfoRow(label: 'Coloração', value: species.coloration),
                        _divider(context),
                        InfoRow(label: 'Comportamento', value: species.behaviour),
                        _divider(context),
                        InfoRow(
                          label: 'Habitats',
                          value: species.habitats.join(', '),
                        ),
                      ],
                    ),
                  ),
                ),
                AppSpacing.gapXxl,

                // Distribuição (mapa é placeholder até a Fase 7).
                AppSection(
                  title: AppStrings.speciesDistribution,
                  icon: Icons.public_rounded,
                  child: _DistributionPanel(species: species),
                ),
                AppSpacing.gapXxl,

                // Morfologia.
                //
                // É aqui que o visualizador 3D vai encaixar na Fase 7: o slot
                // já ocupa o espaço e a lista de estruturas abaixo dele é a
                // mesma que virará os pontos tocáveis sobre o modelo (§24).
                AppSection(
                  title: AppStrings.speciesMorphology,
                  icon: Icons.pest_control_outlined,
                  child: Column(
                    children: <Widget>[
                      Model3DSlot(species: species),
                      AppSpacing.gapMd,
                      MorphologySection(features: species.morphology),
                    ],
                  ),
                ),
                AppSpacing.gapXxl,

                // Relevância médica — sempre acompanhada de aviso.
                AppSection(
                  title: AppStrings.speciesMedical,
                  icon: Icons.medical_information_outlined,
                  child: MedicalRelevancePanel(species: species),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) =>
      Divider(height: 1, color: context.colors.border);
}

/// Cabeçalho que colapsa: a placa da espécie recua enquanto o usuário rola.
class _SpeciesAppBar extends StatelessWidget {
  const _SpeciesAppBar({required this.species});

  final Species species;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return SliverAppBar(
      pinned: true,
      expandedHeight: 240,
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      leading: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: CircleAvatar(
          backgroundColor: c.scrim,
          child: IconButton(
            tooltip: AppStrings.back,
            icon: Icon(Icons.arrow_back_rounded, color: c.onMedia),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        title: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            // O título só aparece quando o cabeçalho está recolhido.
            final bool collapsed = constraints.biggest.height <= 96;
            return AnimatedOpacity(
              opacity: collapsed ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: ScientificName(
                species.scientificName,
                scale: ScientificNameScale.medium,
                color: c.textPrimary,
              ),
            );
          },
        ),
        background: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            SpeciesPlate(species: species, borderRadius: BorderRadius.zero),
            // Gradiente para o texto do rodapé respirar.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    c.background.withValues(alpha: 0),
                    c.background.withValues(alpha: 0.4),
                    c.background,
                  ],
                  stops: const <double>[0.4, 0.8, 1],
                ),
              ),
            ),
            Positioned(
              left: AppSpacing.screenGutter,
              right: AppSpacing.screenGutter,
              bottom: AppSpacing.lg,
              child: SpeciesNamePair(
                scientificName: species.scientificName,
                commonName: species.commonName,
                scale: ScientificNameScale.large,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DistributionPanel extends StatelessWidget {
  const _DistributionPanel({required this.species});

  final Species species;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Column(
      children: <Widget>[
        // Placeholder de mapa — reservado para a Fase 7.
        Container(
          height: 150,
          decoration: BoxDecoration(
            color: c.surfaceSunken,
            borderRadius: AppRadii.brMd,
            border: Border.all(color: c.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.map_outlined, size: AppSizing.iconXl, color: c.textTertiary),
              const SizedBox(height: AppSpacing.sm),
              Text(
                AppStrings.mapPlaceholder,
                style: context.text.bodySmall.copyWith(color: c.textTertiary),
              ),
            ],
          ),
        ),
        AppSpacing.gapMd,
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            for (final String region in species.distribution)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: c.primarySoft,
                  borderRadius: AppRadii.brPill,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.place_outlined, size: AppSizing.iconXs, color: c.primary),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      region,
                      style: context.text.labelSmall.copyWith(color: c.primary),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
