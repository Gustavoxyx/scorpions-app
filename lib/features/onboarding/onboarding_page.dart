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
import '../../state/onboarding_controller.dart';
import 'widgets/onboarding_illustration.dart';

/// Modelo de um passo da apresentação.
class _OnboardingStep {
  const _OnboardingStep({
    required this.title,
    required this.body,
    required this.illustration,
    this.warning,
  });

  final String title;
  final String body;
  final OnboardingArt illustration;
  final String? warning;
}

/// Três telas de apresentação.
///
/// A terceira não é decorativa: ela estabelece o limite do produto antes de o
/// usuário criar expectativa. Um app que promete identificar espécies precisa
/// dizer, logo na abertura, que pode errar e que não substitui um médico.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _index = 0;

  static const List<_OnboardingStep> _steps = <_OnboardingStep>[
    _OnboardingStep(
      title: AppStrings.onb1Title,
      body: AppStrings.onb1Body,
      illustration: OnboardingArt.capture,
    ),
    _OnboardingStep(
      title: AppStrings.onb2Title,
      body: AppStrings.onb2Body,
      illustration: OnboardingArt.knowledge,
    ),
    _OnboardingStep(
      title: AppStrings.onb3Title,
      body: AppStrings.onb3Body,
      illustration: OnboardingArt.safety,
      warning: AppStrings.onb3Warning,
    ),
  ];

  bool get _isLast => _index == _steps.length - 1;

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: AppMotion.page,
      curve: AppMotion.emphasized,
    );
  }

  void _finish() {
    context.read<OnboardingController>().complete();
    context.go(AppRoutes.login);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.maxContentWidth),
            child: Column(
              children: <Widget>[
                // Cabeçalho: "Pular" só faz sentido antes do último passo.
                SizedBox(
                  height: 48,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AnimatedOpacity(
                      opacity: _isLast ? 0 : 1,
                      duration: AppMotion.base,
                      child: IgnorePointer(
                        ignoring: _isLast,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            right: AppSpacing.screenGutter,
                          ),
                          child: AppButton(
                            label: AppStrings.skip,
                            variant: AppButtonVariant.ghost,
                            size: AppButtonSize.small,
                            expand: false,
                            onPressed: _finish,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _steps.length,
                    onPageChanged: (int i) => setState(() => _index = i),
                    itemBuilder: (BuildContext context, int i) =>
                        _StepView(step: _steps[i]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    AppSpacing.lg,
                    AppSpacing.screenGutter,
                    AppSpacing.xl,
                  ),
                  child: Column(
                    children: <Widget>[
                      _ProgressDots(count: _steps.length, index: _index),
                      AppSpacing.gapXl,
                      AppButton(
                        label: _isLast
                            ? AppStrings.continueLabel
                            : AppStrings.continueLabel,
                        icon: _isLast ? Icons.check_rounded : null,
                        trailingIcon:
                            _isLast ? null : Icons.arrow_forward_rounded,
                        onPressed: _next,
                        glow: _isLast,
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

class _StepView extends StatelessWidget {
  const _StepView({required this.step});

  final _OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: AppSpacing.screen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // A ilustração encolhe em telas baixas para nunca causar overflow.
          SizedBox(
            height: (context.screenHeight * 0.32).clamp(180.0, 300.0),
            width: double.infinity,
            child: OnboardingIllustration(art: step.illustration),
          ),
          AppSpacing.gapXxxl,
          Text(step.title, style: context.text.display),
          AppSpacing.gapMd,
          Text(step.body, style: context.text.body),
          if (step.warning != null) ...<Widget>[
            AppSpacing.gapXl,
            DisclaimerBanner(
              message: step.warning!,
              tone: DisclaimerTone.caution,
              icon: Icons.medical_information_outlined,
            ),
          ],
        ],
      ),
    );
  }
}

/// Indicador de progresso: o passo atual vira uma barra, os demais são pontos.
class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(count, (int i) {
        final bool active = i == index;
        return AnimatedContainer(
          duration: AppMotion.base,
          curve: AppMotion.emphasized,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          height: 5,
          width: active ? 28 : 5,
          decoration: BoxDecoration(
            color: active ? c.primary : c.borderStrong,
            borderRadius: AppRadii.brPill,
          ),
        );
      }),
    );
  }
}
