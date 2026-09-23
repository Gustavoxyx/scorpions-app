import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router/app_router.dart';
import '../../app/router/app_routes.dart';
import '../../core/constants/app_config.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/scorpion_mark.dart';
import '../../state/auth_controller.dart';
import '../../state/onboarding_controller.dart';

/// Primeira tela.
///
/// A animação é o gesto de identidade do produto: a marca surge escura e
/// "acende" em ultravioleta — a referência é a fluorescência real do exoesqueleto
/// do escorpião sob luz UV. Dura pouco mais de um segundo e meio; um splash
/// longo é desrespeito com o tempo de quem abre o aplicativo.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  late final Animation<double> _markOpacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.35, curve: AppMotion.decelerate),
  );

  late final Animation<double> _markScale = Tween<double>(
    begin: 0.86,
    end: 1,
  ).animate(CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.55, curve: AppMotion.emphasized),
  ));

  /// O halo cresce e estabiliza — o "acender" da fluorescência.
  late final Animation<double> _glow = TweenSequence<double>(
    <TweenSequenceItem<double>>[
      TweenSequenceItem<double>(tween: ConstantTween<double>(0), weight: 25),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0, end: 1)
            .chain(CurveTween(curve: Curves.easeOutSine)),
        weight: 40,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 0.72),
        weight: 35,
      ),
    ],
  ).animate(_controller);

  late final Animation<double> _wordOpacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.45, 0.8, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _scheduleExit();
  }

  Future<void> _scheduleExit() async {
    await Future<void>.delayed(const Duration(milliseconds: 1750));
    if (!mounted) return;

    final OnboardingController onboarding = context.read<OnboardingController>();
    final AuthController auth = context.read<AuthController>();

    // Um link profundo só é honrado se o usuário puder mesmo chegar lá: com a
    // apresentação pendente ou sem sessão, o destino guardado é descartado e o
    // fluxo normal assume.
    final String? deepLink = AppRouter.takePendingDeepLink();
    final bool followDeepLink =
        deepLink != null && onboarding.completed && auth.isAuthenticated;

    final String destination = followDeepLink
        ? deepLink
        : !onboarding.completed
            ? AppRoutes.onboarding
            : auth.isAuthenticated
                ? AppRoutes.home
                : AppRoutes.login;

    context.go(destination);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Opacity(
                  opacity: _markOpacity.value,
                  child: Transform.scale(
                    scale: _markScale.value,
                    child: ScorpionMark(size: 108, glow: _glow.value),
                  ),
                ),
                AppSpacing.gapXxl,
                Opacity(
                  opacity: _wordOpacity.value,
                  child: Column(
                    children: <Widget>[
                      Text(
                        AppConfig.appName.toUpperCase(),
                        style: context.text.h2.copyWith(letterSpacing: 9),
                      ),
                      AppSpacing.gapSm,
                      Text(
                        AppConfig.appTagline,
                        textAlign: TextAlign.center,
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
