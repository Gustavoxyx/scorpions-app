import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/scorpion_mark.dart';
import '../../camera/widgets/frame_guide.dart';

enum OnboardingArt { capture, knowledge, safety }

/// Ilustrações da apresentação inicial.
///
/// São construídas com os mesmos elementos do aplicativo (a marca vetorial, a
/// moldura da câmera, a tipografia do catálogo) em vez de arte importada. O
/// efeito é que o onboarding mostra o produto de verdade — e não há um único
/// arquivo de imagem para manter.
class OnboardingIllustration extends StatelessWidget {
  const OnboardingIllustration({super.key, required this.art});

  final OnboardingArt art;

  @override
  Widget build(BuildContext context) {
    return switch (art) {
      OnboardingArt.capture => const _CaptureArt(),
      OnboardingArt.knowledge => const _KnowledgeArt(),
      OnboardingArt.safety => const _SafetyArt(),
    };
  }
}

/// Passo 1: a moldura de captura com o espécime centralizado.
class _CaptureArt extends StatelessWidget {
  const _CaptureArt();

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double side = constraints.maxHeight;
        return Center(
          child: SizedBox(
            width: side * 0.86,
            height: side,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: AppRadii.brXl,
                    border: Border.all(color: c.border),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: FrameGuide(
                    color: c.primary,
                    child: Center(child: ScorpionMark(size: side * 0.34)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Passo 2: uma ficha de espécie esquemática.
class _KnowledgeArt extends StatelessWidget {
  const _KnowledgeArt();

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double side = constraints.maxHeight;
        return Center(
          child: Container(
            width: side * 0.94,
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: AppRadii.brXl,
              border: Border.all(color: c.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: side * 0.22,
                      height: side * 0.22,
                      decoration: BoxDecoration(
                        color: c.surfaceSunken,
                        borderRadius: AppRadii.brSm,
                        border: Border.all(color: c.border),
                      ),
                      child: Center(child: ScorpionMark(size: side * 0.13)),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _Bar(width: 0.82, color: c.textPrimary, height: 9),
                          const SizedBox(height: AppSpacing.sm),
                          _Bar(width: 0.55, color: c.textTertiary, height: 7),
                          const SizedBox(height: AppSpacing.md),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: c.primarySoft,
                              borderRadius: AppRadii.brPill,
                            ),
                            child: Text(
                              'ALTA CONFIANÇA',
                              style: context.text.micro.copyWith(color: c.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                _Bar(width: 1, color: c.textTertiary, height: 6),
                const SizedBox(height: AppSpacing.sm),
                _Bar(width: 0.92, color: c.textTertiary, height: 6),
                const SizedBox(height: AppSpacing.sm),
                _Bar(width: 0.64, color: c.textTertiary, height: 6),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Passo 3: o limite do produto — o sistema também sabe dizer "não sei".
class _SafetyArt extends StatelessWidget {
  const _SafetyArt();

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double side = constraints.maxHeight;
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Container(
                  width: side * 0.82,
                  height: side * 0.82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.surface,
                    border: Border.all(color: c.border),
                  ),
                ),
                Container(
                  width: side * 0.58,
                  height: side * 0.58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.warningSoft,
                    border: Border.all(color: c.secondary.withValues(alpha: 0.35)),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.shield_outlined,
                      size: side * 0.2,
                      color: c.secondary,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'NÃO SEI',
                      style: context.text.overlineSmall.copyWith(color: c.secondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Barra de texto esquemático usada nas ilustrações.
class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.color, required this.height});

  final double width;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: width,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.22),
          borderRadius: AppRadii.brPill,
        ),
      ),
    );
  }
}
