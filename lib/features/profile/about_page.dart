import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_config.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/feedback_states.dart';
import '../../core/widgets/list_items.dart';
import '../../core/widgets/scorpion_mark.dart';
import '../../state/onboarding_controller.dart';

/// Tela "Sobre".
///
/// Reúne identidade do produto, aviso de responsabilidade e um ponto de entrada
/// para rever a apresentação inicial. É também onde deixamos explícito o status
/// de protótipo — transparência com quem usa.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return AppScaffold(
      title: AppStrings.aboutTitle,
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppSpacing.gapLg,
          const Center(child: ScorpionMark(size: 76, glow: 0.5)),
          AppSpacing.gapLg,
          Center(
            child: Text(
              AppConfig.appName.toUpperCase(),
              style: context.text.h2.copyWith(letterSpacing: 6),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: Text(
              AppConfig.appTagline,
              textAlign: TextAlign.center,
              style: context.text.bodySmall,
            ),
          ),
          AppSpacing.gapSm,
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: c.warningSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                AppConfig.phaseLabel,
                style: context.text.labelSmall.copyWith(color: c.secondary),
              ),
            ),
          ),
          AppSpacing.gapXxl,
          AppCard(
            child: Text(
              'Este aplicativo usa inteligência artificial para estimar a '
              'espécie de um escorpião a partir de uma fotografia. Nesta versão '
              'de demonstração, as identificações são simuladas — servem para '
              'validar a experiência antes de conectarmos o modelo real.',
              style: context.text.body,
            ),
          ),
          AppSpacing.gapLg,
          const DisclaimerBanner(
            message: AppStrings.medicalDisclaimer,
            tone: DisclaimerTone.caution,
            icon: Icons.medical_information_outlined,
          ),
          AppSpacing.gapXxl,
          AppTileGroup(
            children: <Widget>[
              AppNavTile(
                label: 'Rever apresentação',
                icon: Icons.slideshow_outlined,
                onTap: () => context.read<OnboardingController>().replay(),
              ),
              const AppNavTile(
                label: 'Versão',
                icon: Icons.tag_rounded,
                value: AppConfig.version,
                showChevron: false,
              ),
            ],
          ),
          AppSpacing.gapXxl,
          Center(
            child: Text(
              'Feito para estudantes, pesquisadores e curiosos.',
              style: context.text.bodySmall
                  .copyWith(color: c.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
