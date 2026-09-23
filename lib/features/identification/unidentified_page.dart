import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/feedback_states.dart';
import '../../core/widgets/reveal.dart';
import '../../core/widgets/specimen_image.dart';
import '../../data/models/identification.dart';
import '../../state/identification_controller.dart';
import '../../core/theme/app_sizing.dart';

/// Tela de resultado negativo.
///
/// Esta tela é uma declaração de princípio do produto: o sistema PODE dizer
/// "não sei". Ela é tratada com o mesmo cuidado visual do resultado positivo —
/// não é um erro escondido, é uma resposta legítima. O tom é de orientação
/// ("tente assim"), não de falha.
class UnidentifiedPage extends StatelessWidget {
  const UnidentifiedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final IdentificationResult? result =
        context.watch<IdentificationController>().lastResult;

    if (result == null || !result.isRejected) {
      return Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: ErrorState(
            title: 'Sem dados',
            message: 'Nada para exibir.',
            onRetry: () => context.go(AppRoutes.home),
          ),
        ),
      );
    }

    final RejectionReason reason = result.rejectionReason!;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.maxContentWidth),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: Reveal.stagger(<Widget>[
                  Row(
                    children: <Widget>[
                      AppIconButton(
                        icon: Icons.close_rounded,
                        tooltip: AppStrings.close,
                        size: 40,
                        onPressed: () => context.go(AppRoutes.home),
                      ),
                      const Spacer(),
                      const MockDataBadge(compact: true),
                    ],
                  ),
                  AppSpacing.gapXl,
                  // Ícone-símbolo do "não sei": escudo, não erro.
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.warningSoft,
                        border: Border.all(
                          color: c.secondary.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Icon(Icons.help_outline_rounded,
                          size: 44, color: c.secondary),
                    ),
                  ),
                  AppSpacing.gapXxl,
                  Text(
                    AppStrings.unidentifiedTitle,
                    textAlign: TextAlign.center,
                    style: context.text.h2,
                  ),
                  AppSpacing.gapMd,
                  Text(
                    AppStrings.unidentifiedBody,
                    textAlign: TextAlign.center,
                    style: context.text.body,
                  ),
                  AppSpacing.gapXl,
                  // A foto submetida, para o usuário reavaliar a qualidade.
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: CapturedPhoto(image: result.image),
                  ),
                  AppSpacing.gapXl,
                  _ReasonCard(reason: reason),
                  AppSpacing.gapXl,
                  AppButton(
                    label: AppStrings.tryAgain,
                    icon: Icons.camera_alt_rounded,
                    glow: true,
                    onPressed: () {
                      context.read<IdentificationController>().reset();
                      context.pushReplacement(AppRoutes.capture);
                    },
                  ),
                  AppSpacing.gapSm,
                  AppButton(
                    label: AppStrings.choosePhoto,
                    icon: Icons.photo_library_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: () {
                      context.read<IdentificationController>().reset();
                      context.pushReplacement(AppRoutes.capture);
                    },
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReasonCard extends StatelessWidget {
  const _ReasonCard({required this.reason});

  final RejectionReason reason;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(AppStrings.unidentifiedWhy.toUpperCase(),
              style: context.text.overline),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: c.surfaceSunken,
                  borderRadius: AppRadii.brSm,
                ),
                child: Icon(Icons.search_off_rounded, size: AppSizing.iconMd, color: c.secondary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(reason.title, style: context.text.h4),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(reason.hint, style: context.text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
