import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_sizing.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/confidence_badge.dart';
import '../../core/widgets/feedback_states.dart';
import '../../core/widgets/specimen_image.dart';
import '../../data/models/identification.dart';
import '../../data/models/species.dart';
import '../../state/identification_controller.dart';
import '../species/widgets/model_3d_slot.dart';

/// Tela de resultado (identificação bem-sucedida).
///
/// Aqui mora a "sensação de descoberta" pedida no briefing. A revelação é
/// encenada em ordem deliberada: primeiro a foto, depois o nome científico,
/// depois o medidor de confiança, depois os detalhes e por último a ação. Cada
/// elemento entra com um pequeno atraso, de modo que o olho seja conduzido do
/// espécime até a conclusão.
///
/// O selo de dado simulado nunca sai da tela enquanto a IA real não existir.
class ResultPage extends StatelessWidget {
  const ResultPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final IdentificationResult? result =
        context.watch<IdentificationController>().lastResult;

    // Salvaguarda contra abertura direta sem resultado.
    if (result == null || result.isRejected) {
      return Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: ErrorState(
            title: 'Sem resultado',
            message: 'Nenhuma identificação para exibir.',
            onRetry: () => context.go(AppRoutes.home),
          ),
        ),
      );
    }

    final SpeciesPrediction top = result.top;
    final Species species = top.species;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.maxContentWidth),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: <Widget>[
                SliverToBoxAdapter(
                  child: _ResultHeader(onClose: () => context.go(AppRoutes.home)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    0,
                    AppSpacing.screenGutter,
                    AppSpacing.xxxl,
                  ),
                  sliver: SliverList.list(
                    children: <Widget>[
                      // 1 — a fotografia.
                      _Stage(
                        order: 0,
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: CapturedPhoto(image: result.image),
                        ),
                      ),
                      AppSpacing.gapXl,
                      // 2 — o nome.
                      _Stage(
                        order: 1,
                        child: _Identity(species: species),
                      ),
                      AppSpacing.gapXl,
                      // 3 — a confiança.
                      _Stage(
                        order: 2,
                        child: _ConfidencePanel(prediction: top),
                      ),
                      AppSpacing.gapLg,
                      // 4 — os detalhes.
                      _Stage(
                        order: 3,
                        child: _Details(
                          species: species,
                          createdAt: result.createdAt,
                        ),
                      ),
                      AppSpacing.gapLg,
                      // 5 — o espaço reservado à exploração tridimensional.
                      // Aparece inativo enquanto não houver modelo (§20).
                      _Stage(
                        order: 4,
                        child: Model3DSlot(species: species, compact: true),
                      ),
                      if (result.alternatives.isNotEmpty) ...<Widget>[
                        AppSpacing.gapLg,
                        _Stage(
                          order: 5,
                          child: _Alternatives(
                            alternatives: result.alternatives,
                          ),
                        ),
                      ],
                      AppSpacing.gapXl,
                      // 5 — a ação.
                      _Stage(
                        order: 6,
                        child: AppButton(
                          label: AppStrings.resultFullInfo,
                          trailingIcon: Icons.arrow_forward_rounded,
                          glow: true,
                          onPressed: () => context.push(
                            AppRoutes.species(species.id),
                            extra: species,
                          ),
                        ),
                      ),
                      AppSpacing.gapMd,
                      _Stage(
                        order: 6,
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(Icons.check_circle_outline_rounded,
                                  size: AppSizing.iconSm,
                                  color: c.textTertiary),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                AppStrings.resultSavedToHistory,
                                style: context.text.bodySmall
                                    .copyWith(color: c.textTertiary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Envelope de revelação escalonada.
class _Stage extends StatelessWidget {
  const _Stage({required this.order, required this.child});

  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _RevealDelayed(
      // O nome espera a foto; a confiança espera o nome; e assim por diante.
      //
      // O fator é 0.28 e não 0.4: com sete etapas, o passo maior empurrava o
      // último bloco para quase dois segundos depois da abertura — tempo em que
      // o usuário já rolou a tela e viu espaço vazio. A sensação de descoberta
      // depende do encadeamento, não da lentidão.
      delay: AppMotion.reveal * 0.28 * order,
      child: child,
    );
  }
}

/// Reveal com atraso proporcional — versão local para orquestrar a sequência.
class _RevealDelayed extends StatefulWidget {
  const _RevealDelayed({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<_RevealDelayed> createState() => _RevealDelayedState();
}

class _RevealDelayedState extends State<_RevealDelayed>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.slow,
  );

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    final CurvedAnimation anim =
        CurvedAnimation(parent: _controller, curve: AppMotion.decelerate);
    return AnimatedBuilder(
      animation: anim,
      builder: (BuildContext context, Widget? child) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - anim.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      child: Row(
        children: <Widget>[
          AppIconButton(
            icon: Icons.close_rounded,
            tooltip: AppStrings.close,
            size: 40,
            onPressed: onClose,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(AppStrings.resultTitle, style: context.text.h2),
          ),
          const MockDataBadge(compact: true),
        ],
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.species});

  final Species species;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          species.scientificName,
          style: context.text.scientificNameHero,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(species.commonName, style: context.text.h3),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${species.family} · ${species.genus}',
          style: context.text.bodySmall,
        ),
      ],
    );
  }
}

class _ConfidencePanel extends StatelessWidget {
  const _ConfidencePanel({required this.prediction});

  final SpeciesPrediction prediction;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return AppCard(
      accent: true,
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              ConfidenceMeter(
                score: prediction.score,
                level: prediction.level,
                size: 120,
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ConfidenceBadge(level: prediction.level),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      prediction.level.guidance,
                      style: context.text.bodySmall.copyWith(height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(color: c.border, height: 1),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Icon(Icons.info_outline_rounded, size: AppSizing.iconSm, color: c.textTertiary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Estimativa gerada por dados simulados. Não use para decisão '
                  'médica.',
                  style: context.text.caption.copyWith(color: c.textTertiary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.species, required this.createdAt});

  final Species species;
  final DateTime createdAt;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _row(context, Icons.place_outlined, AppStrings.resultRegion,
              species.distributionSummary),
          const SizedBox(height: AppSpacing.md),
          _row(context, Icons.straighten_rounded, 'Tamanho', species.sizeRange),
          const SizedBox(height: AppSpacing.md),
          _row(context, Icons.event_outlined, 'Análise',
              Formatters.dateTime(createdAt)),
          const SizedBox(height: AppSpacing.lg),
          Text(
            AppStrings.resultSummary.toUpperCase(),
            style: context.text.overline,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(species.summary, style: context.text.bodySmall),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    final AppColors c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: AppSizing.iconMd, color: c.primary),
        const SizedBox(width: AppSpacing.md),
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: context.text.bodySmall.copyWith(color: c.textTertiary),
          ),
        ),
        Expanded(child: Text(value, style: context.text.h4)),
      ],
    );
  }
}

/// Hipóteses alternativas.
///
/// Mostrá-las é uma escolha de honestidade científica: uma identificação não é
/// um oráculo, e o usuário merece ver o que mais o sistema considerou.
class _Alternatives extends StatelessWidget {
  const _Alternatives({required this.alternatives});

  final List<SpeciesPrediction> alternatives;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('OUTRAS HIPÓTESES', style: context.text.overline),
          const SizedBox(height: AppSpacing.sm),
          for (final SpeciesPrediction p in alternatives)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      p.species.scientificName,
                      style: context.text.scientificNameSmall
                          .copyWith(fontSize: context.text.bodySmall.fontSize)
                          .copyWith(color: c.textSecondary),
                    ),
                  ),
                  Text(
                    Formatters.percent(p.score),
                    style:
                        context.text.monoSmall.copyWith(color: c.textTertiary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
