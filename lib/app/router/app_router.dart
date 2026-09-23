import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/feedback_states.dart';
import '../../data/models/species.dart';
import '../../features/auth/forgot_password_page.dart';
import '../../features/auth/login_page.dart';
import '../../features/auth/register_page.dart';
import '../../features/camera/capture_page.dart';
import '../../features/camera/confirm_photo_page.dart';
import '../../features/catalog/catalog_page.dart';
import '../../features/history/history_page.dart';
import '../../features/home/home_page.dart';
import '../../features/home/photo_tips_page.dart';
import '../../features/identification/analyzing_page.dart';
import '../../features/identification/result_page.dart';
import '../../features/identification/unidentified_page.dart';
import '../../features/onboarding/onboarding_page.dart';
import '../../features/profile/about_page.dart';
import '../../features/profile/profile_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/shell/app_shell.dart';
import '../../features/species/species_detail_page.dart';
import '../../features/splash/splash_page.dart';
import '../../state/auth_controller.dart';
import '../../state/onboarding_controller.dart';
import 'app_routes.dart';
import 'page_transitions.dart';

/// Configuração de navegação.
///
/// Duas decisões estruturais:
///
/// 1. `StatefulShellRoute.indexedStack` para as quatro abas — cada aba mantém
///    a própria pilha e o próprio scroll ao alternar, que é o comportamento
///    esperado de um app móvel sério.
/// 2. O fluxo de identificação (câmera → confirmação → análise → resultado)
///    fica no navegador raiz, ACIMA da barra de abas. A captura é uma mudança
///    de modo, não uma quinta aba: o botão da câmera é o coração do produto e
///    ocupa a tela inteira.
///
/// O guarda de rota concentra as regras de acesso; nenhuma tela chama
/// `Navigator.pushReplacement` para "consertar" o estado de sessão.
abstract final class AppRouter {
  static final GlobalKey<NavigatorState> _rootKey =
      GlobalKey<NavigatorState>(debugLabel: 'root');
  static final GlobalKey<NavigatorState> _shellKey =
      GlobalKey<NavigatorState>(debugLabel: 'shell');

  static GoRouter create({
    required AuthController auth,
    required OnboardingController onboarding,
  }) {
    return GoRouter(
      navigatorKey: _rootKey,
      initialLocation: AppRoutes.splash,
      debugLogDiagnostics: false,
      refreshListenable: Listenable.merge(<Listenable>[auth, onboarding]),
      redirect: (BuildContext context, GoRouterState state) =>
          _guard(state, auth: auth, onboarding: onboarding),
      errorBuilder: (BuildContext context, GoRouterState state) => Scaffold(
        body: ErrorState(
          title: 'Rota não encontrada',
          message: 'O endereço "${state.uri}" não existe neste aplicativo.',
          onRetry: () => context.go(AppRoutes.home),
        ),
      ),
      routes: <RouteBase>[
        GoRoute(
          path: AppRoutes.splash,
          pageBuilder: (BuildContext c, GoRouterState s) =>
              AppTransitions.fade(key: s.pageKey, child: const SplashPage()),
        ),
        GoRoute(
          path: AppRoutes.onboarding,
          pageBuilder: (BuildContext c, GoRouterState s) =>
              AppTransitions.fade(key: s.pageKey, child: const OnboardingPage()),
        ),
        GoRoute(
          path: AppRoutes.login,
          pageBuilder: (BuildContext c, GoRouterState s) =>
              AppTransitions.fade(key: s.pageKey, child: const LoginPage()),
        ),
        GoRoute(
          path: AppRoutes.register,
          pageBuilder: (BuildContext c, GoRouterState s) => AppTransitions
              .forward(key: s.pageKey, child: const RegisterPage()),
        ),
        GoRoute(
          path: AppRoutes.forgotPassword,
          pageBuilder: (BuildContext c, GoRouterState s) => AppTransitions
              .forward(key: s.pageKey, child: const ForgotPasswordPage()),
        ),

        // ---- Abas -----------------------------------------------------------
        StatefulShellRoute.indexedStack(
          builder: (
            BuildContext context,
            GoRouterState state,
            StatefulNavigationShell shell,
          ) =>
              AppShell(shell: shell),
          branches: <StatefulShellBranch>[
            StatefulShellBranch(
              navigatorKey: _shellKey,
              routes: <RouteBase>[
                GoRoute(
                  path: AppRoutes.home,
                  pageBuilder: (BuildContext c, GoRouterState s) =>
                      AppTransitions.tab(key: s.pageKey, child: const HomePage()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: AppRoutes.history,
                  pageBuilder: (BuildContext c, GoRouterState s) =>
                      AppTransitions.tab(
                          key: s.pageKey, child: const HistoryPage()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: AppRoutes.catalog,
                  pageBuilder: (BuildContext c, GoRouterState s) =>
                      AppTransitions.tab(
                          key: s.pageKey, child: const CatalogPage()),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: AppRoutes.profile,
                  pageBuilder: (BuildContext c, GoRouterState s) =>
                      AppTransitions.tab(
                          key: s.pageKey, child: const ProfilePage()),
                  routes: <RouteBase>[
                    GoRoute(
                      path: 'settings',
                      parentNavigatorKey: _rootKey,
                      pageBuilder: (BuildContext c, GoRouterState s) =>
                          AppTransitions.forward(
                              key: s.pageKey, child: const SettingsPage()),
                    ),
                    GoRoute(
                      path: 'about',
                      parentNavigatorKey: _rootKey,
                      pageBuilder: (BuildContext c, GoRouterState s) =>
                          AppTransitions.forward(
                              key: s.pageKey, child: const AboutPage()),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),

        // ---- Fluxo de identificação (tela cheia) -----------------------------
        GoRoute(
          path: AppRoutes.capture,
          parentNavigatorKey: _rootKey,
          pageBuilder: (BuildContext c, GoRouterState s) =>
              AppTransitions.modal(key: s.pageKey, child: const CapturePage()),
        ),
        GoRoute(
          path: AppRoutes.confirmPhoto,
          parentNavigatorKey: _rootKey,
          pageBuilder: (BuildContext c, GoRouterState s) => AppTransitions
              .forward(key: s.pageKey, child: const ConfirmPhotoPage()),
        ),
        GoRoute(
          path: AppRoutes.analyzing,
          parentNavigatorKey: _rootKey,
          pageBuilder: (BuildContext c, GoRouterState s) =>
              AppTransitions.modal(key: s.pageKey, child: const AnalyzingPage()),
        ),
        GoRoute(
          path: AppRoutes.result,
          parentNavigatorKey: _rootKey,
          pageBuilder: (BuildContext c, GoRouterState s) =>
              AppTransitions.fade(key: s.pageKey, child: const ResultPage()),
        ),
        GoRoute(
          path: AppRoutes.unidentified,
          parentNavigatorKey: _rootKey,
          pageBuilder: (BuildContext c, GoRouterState s) => AppTransitions.fade(
              key: s.pageKey, child: const UnidentifiedPage()),
        ),
        GoRoute(
          path: AppRoutes.photoTips,
          parentNavigatorKey: _rootKey,
          pageBuilder: (BuildContext c, GoRouterState s) => AppTransitions
              .forward(key: s.pageKey, child: const PhotoTipsPage()),
        ),
        GoRoute(
          path: AppRoutes.speciesPattern,
          parentNavigatorKey: _rootKey,
          pageBuilder: (BuildContext c, GoRouterState s) {
            // A espécie pode chegar pronta (vinda do resultado) ou apenas pelo
            // id (link direto, histórico) — nesse caso a tela a busca no
            // repositório.
            final Object? extra = s.extra;
            return AppTransitions.forward(
              key: s.pageKey,
              child: SpeciesDetailPage(
                speciesId: s.pathParameters['id']!,
                preloaded: extra is Species ? extra : null,
              ),
            );
          },
        ),
      ],
    );
  }

  /// Destino pretendido quando o aplicativo foi aberto por um link profundo.
  ///
  /// Na abertura a sessão ainda não foi resolvida, então a guarda manda todo
  /// mundo para o splash — e o endereço original se perderia. Guardamos ele
  /// aqui para que o splash saiba para onde ir quando a animação terminar.
  ///
  /// Passa a importar de verdade na Fase 3, quando notificações e links de
  /// espécie compartilhada abrirem o app numa tela específica: sem isto, todo
  /// link cairia na Home.
  static String? _pendingDeepLink;

  /// Consome o destino pendente. O splash chama uma única vez.
  static String? takePendingDeepLink() {
    final String? link = _pendingDeepLink;
    _pendingDeepLink = null;
    return link;
  }

  /// Guarda única de acesso.
  static String? _guard(
    GoRouterState state, {
    required AuthController auth,
    required OnboardingController onboarding,
  }) {
    final String location = state.matchedLocation;

    // Enquanto a sessão não foi resolvida, ninguém sai do splash. Sem isso, a
    // tela de login pisca antes da restauração de sessão da Fase 3.
    if (auth.isResolving) {
      if (location == AppRoutes.splash) return null;
      // Guarda o destino real antes de desviar para o splash.
      if (!AppRoutes.publicRoutes.contains(location)) {
        _pendingDeepLink = state.uri.toString();
      }
      return AppRoutes.splash;
    }

    // O splash decide sozinho para onde ir quando a animação termina.
    if (location == AppRoutes.splash) return null;

    if (!onboarding.completed) {
      return location == AppRoutes.onboarding ? null : AppRoutes.onboarding;
    }

    final bool isPublic = AppRoutes.publicRoutes.contains(location);

    if (!auth.isAuthenticated) {
      return isPublic && location != AppRoutes.onboarding
          ? null
          : AppRoutes.login;
    }

    // Autenticado não volta para telas de autenticação.
    if (isPublic) return AppRoutes.home;

    return null;
  }
}
