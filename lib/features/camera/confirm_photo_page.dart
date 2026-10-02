import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizing.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/feedback_states.dart';
import '../../core/widgets/reveal.dart';
import '../../core/widgets/specimen_image.dart';
import '../../data/models/captured_image.dart';
import '../../data/models/processed_image.dart';
import '../../state/identification_controller.dart';
import 'widgets/frame_guide.dart';
import 'widgets/photo_quality_notice.dart';

/// Confirmação da foto capturada.
///
/// É um passo curto mas importante do produto: dá ao usuário a chance de
/// descartar uma foto ruim ANTES de gastar a análise. Na Fase 5 isso poupa
/// inferências caras; aqui, estabelece o hábito.
class ConfirmPhotoPage extends StatefulWidget {
  const ConfirmPhotoPage({super.key});

  @override
  State<ConfirmPhotoPage> createState() => _ConfirmPhotoPageState();
}

class _ConfirmPhotoPageState extends State<ConfirmPhotoPage> {
  @override
  void initState() {
    super.initState();
    // A inspeção começa sozinha ao abrir a tela: o usuário já está olhando
    // para a foto, e esperar que ele toque em algo para só então descobrir que
    // ela está escura seria desperdiçar justamente o tempo em que ele decide.
    WidgetsBinding.instance.addPostFrameCallback((_) => _inspecionar());
  }

  Future<void> _inspecionar() async {
    if (!mounted) return;
    final IdentificationController c = context.read<IdentificationController>();
    final CapturedImage? imagem = c.pendingImage;
    if (imagem == null || c.preparation != null) return;
    await c.inspect(imagem);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final IdentificationController controller =
        context.watch<IdentificationController>();
    final CapturedImage? image = controller.pendingImage;
    final ImagePreparation? prep = controller.preparation;
    final bool inspecionando = controller.state is IdentificationInspecting;
    final bool podeSeguir = prep?.canProceed ?? false;
    final bool temRessalva =
        podeSeguir && (prep!.quality!.warnings.isNotEmpty);

    // Salvaguarda: se a página for aberta sem imagem pendente (por exemplo,
    // após um hot-restart), voltamos para a captura em vez de quebrar.
    if (image == null) {
      return Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: ErrorState(
            title: 'Nenhuma foto',
            message: 'A imagem não está mais disponível. Capture novamente.',
            onRetry: () => context.pushReplacement(AppRoutes.capture),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.maxContentWidth),
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.screenGutter),
                  child: Row(
                    children: <Widget>[
                      AppIconButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: AppStrings.back,
                        size: AppSizing.minTouchTarget - AppSpacing.sm,
                        onPressed: () => context.pop(),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(AppStrings.confirmTitle,
                            style: context.text.h2),
                      ),
                      const MockDataBadge(compact: true),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenGutter,
                    ),
                    child: Reveal(
                      child: Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: CapturedPhoto(image: image),
                          ),
                          // A mesma moldura da câmera, agora só como referência.
                          Positioned.fill(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.xl),
                              child: FrameGuide(
                                color: c.onMedia,
                                opacity: 0.35,
                                thickness: 2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.screenGutter),
                  child: Column(
                    children: <Widget>[
                      PhotoQualityNotice(preparation: prep),
                      AppSpacing.gapLg,
                      AppButton(
                        // O rótulo muda quando há ressalva: "usar mesmo assim"
                        // diz que a pessoa está escolhendo seguir apesar do
                        // aviso, o que é exatamente o que o §6 pede.
                        label: temRessalva
                            ? AppStrings.usePhotoAnyway
                            : AppStrings.usePhoto,
                        icon: Icons.check_rounded,
                        // O halo é da ação recomendada. Com foto ruim ela deixa
                        // de ser recomendada, então o destaque sai.
                        glow: podeSeguir && !temRessalva,
                        loading: inspecionando,
                        variant: temRessalva
                            ? AppButtonVariant.secondary
                            : AppButtonVariant.primary,
                        onPressed: podeSeguir
                            ? () {
                                controller.submit(image);
                                context.pushReplacement(AppRoutes.analyzing);
                              }
                            : null,
                      ),
                      AppSpacing.gapSm,
                      AppButton(
                        label: AppStrings.retakePhoto,
                        icon: Icons.replay_rounded,
                        variant: AppButtonVariant.secondary,
                        onPressed: () {
                          controller.discardPendingImage();
                          context.pop();
                        },
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
