import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/feedback_states.dart';
import '../../core/widgets/specimen_image.dart';
import '../../state/identification_controller.dart';
import 'widgets/scanner_animation.dart';

/// Tela de análise.
///
/// Reage a [IdentificationController]: quando o estado sai de "analisando", ela
/// redireciona para o resultado, para a rejeição ou para o erro. A tela não
/// decide o desfecho — apenas o encena. Isso é o que permitirá trocar o motor
/// simulado pelo modelo real sem tocar aqui.
class AnalyzingPage extends StatefulWidget {
  const AnalyzingPage({super.key});

  @override
  State<AnalyzingPage> createState() => _AnalyzingPageState();
}

class _AnalyzingPageState extends State<AnalyzingPage> {
  bool _navigated = false;

  void _handleState(IdentificationState state) {
    if (_navigated) return;
    final String? route = switch (state) {
      IdentificationSuccess() => AppRoutes.result,
      IdentificationRejected() => AppRoutes.unidentified,
      IdentificationError() => null, // tratado in-place
      _ => null,
    };
    if (route != null) {
      _navigated = true;
      // Substitui a tela de análise: ela não deve ficar na pilha de volta.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.pushReplacement(route);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final IdentificationController controller =
        context.watch<IdentificationController>();
    final IdentificationState state = controller.state;
    _handleState(state);

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.maxContentWidth),
            child: switch (state) {
              IdentificationError(message: final String message) => ErrorState(
                  title: 'A análise falhou',
                  message: message,
                  onRetry: () => context.pop(),
                ),
              IdentificationAnalyzing() => _AnalyzingView(state: state),
              // Estado transitório enquanto o pós-frame redireciona.
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ),
      ),
    );
  }
}

class _AnalyzingView extends StatelessWidget {
  const _AnalyzingView({required this.state});

  final IdentificationState state;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final IdentificationAnalyzing analyzing = state as IdentificationAnalyzing;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        children: <Widget>[
          const Spacer(),
          const MockDataBadge(),
          AppSpacing.gapXl,
          // Foto sob varredura.
          AspectRatio(
            aspectRatio: 1,
            child: ScannerAnimation(
              child: CapturedPhoto(
                image: analyzing.image,
                borderRadius: AppRadii.brLg,
              ),
            ),
          ),
          AppSpacing.gapXxxl,

          // Contador de etapa. Saber "2 de 5" transforma uma espera indefinida
          // numa espera com fim — é a diferença entre confiar e desistir.
          Text(
            'ETAPA ${analyzing.stageIndex + 1} DE ${analyzing.stageCount}',
            style: context.text.overline.copyWith(color: c.primary),
          ),
          AppSpacing.gapSm,

          // Título e legenda trocam juntos, com transição suave para não
          // "piscar" texto a cada estágio.
          AnimatedSwitcher(
            duration: AppMotion.base,
            transitionBuilder: (Widget child, Animation<double> anim) =>
                FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.25),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: Column(
              key: ValueKey<int>(analyzing.stageIndex),
              children: <Widget>[
                Text(
                  analyzing.message,
                  textAlign: TextAlign.center,
                  style: context.text.h3,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  analyzing.detail,
                  textAlign: TextAlign.center,
                  style: context.text.caption,
                ),
              ],
            ),
          ),
          AppSpacing.gapXl,
          _StageProgress(
            current: analyzing.stageIndex,
            total: analyzing.stageCount,
          ),
          const Spacer(),
          AppButton(
            label: AppStrings.analyzingCancel,
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.small,
            expand: false,
            onPressed: () {
              context.read<IdentificationController>().cancel();
              context.pop();
            },
          ),
        ],
      ),
    );
  }
}

/// Trilha segmentada de estágios — um segmento por etapa da análise.
class _StageProgress extends StatelessWidget {
  const _StageProgress({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Row(
      children: List<Widget>.generate(total, (int i) {
        final bool done = i <= current;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == total - 1 ? 0 : AppSpacing.xs),
            height: 3,
            decoration: BoxDecoration(
              borderRadius: AppRadii.brPill,
              color: c.surfaceSunken,
            ),
            child: AnimatedFractionallySizedBox(
              duration: AppMotion.slow,
              curve: AppMotion.standard,
              alignment: Alignment.centerLeft,
              widthFactor: done ? 1 : 0,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: AppRadii.brPill,
                  color: c.primary,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
