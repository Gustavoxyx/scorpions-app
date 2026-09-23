import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../core/constants/app_config.dart';
import '../core/theme/app_theme.dart';
import '../data/repositories/species_repository.dart';
import '../data/services/camera_service.dart';
import '../data/services/gallery_service.dart';
import '../data/services/identification_service.dart';
import '../state/auth_controller.dart';
import '../state/catalog_controller.dart';
import '../state/history_controller.dart';
import '../state/identification_controller.dart';
import '../state/onboarding_controller.dart';
import '../state/settings_controller.dart';
import 'dependencies.dart';
import 'router/app_router.dart';

/// Raiz da aplicação.
///
/// As implementações concretas vêm de [AppDependencies], que decide entre
/// MOCK, emuladores e Firebase real conforme a configuração do build. Este
/// widget apenas monta os controladores sobre o que recebeu — não conhece
/// nenhuma implementação, e por isso não muda quando a infraestrutura muda.
class ScorpionsApp extends StatefulWidget {
  const ScorpionsApp({super.key, this.dependencies});

  /// Injeção explícita, usada pelos testes. Em produção fica nulo e a
  /// resolução acontece a partir da configuração de build.
  final AppDependencies? dependencies;

  @override
  State<ScorpionsApp> createState() => _ScorpionsAppState();
}

class _ScorpionsAppState extends State<ScorpionsApp> {
  // ---- Composição de dependências -------------------------------------------
  late final AppDependencies _deps =
      widget.dependencies ?? AppDependencies.resolve();

  late final AuthController _auth = AuthController(_deps.authRepository);
  final OnboardingController _onboarding = OnboardingController();
  final SettingsController _settings = SettingsController();
  late final IdentificationController _identification =
      IdentificationController(
    // A identificação continua simulada nesta fase (§40). O que mudou é onde
    // o resultado é gravado, não quem o produz.
    service: MockIdentificationService(),
    repository: _deps.identificationRepository,
  );
  // O histórico observa a sessão: ao trocar de usuário a lista é recarregada,
  // e no logout é esvaziada. Sem isso, o próximo usuário do mesmo aparelho
  // veria por um instante os registros do anterior.
  late final HistoryController _history = HistoryController(
    _deps.identificationRepository,
    authChanges: _deps.authRepository.authStateChanges(),
  );
  late final CatalogController _catalog =
      CatalogController(_deps.speciesRepository);

  late final GoRouter _router = AppRouter.create(
    auth: _auth,
    onboarding: _onboarding,
  );

  @override
  void dispose() {
    _auth.dispose();
    _onboarding.dispose();
    _settings.dispose();
    _identification.dispose();
    _history.dispose();
    _catalog.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<AuthController>.value(value: _auth),
        ChangeNotifierProvider<OnboardingController>.value(value: _onboarding),
        ChangeNotifierProvider<SettingsController>.value(value: _settings),
        ChangeNotifierProvider<IdentificationController>.value(
          value: _identification,
        ),
        ChangeNotifierProvider<HistoryController>.value(value: _history),
        ChangeNotifierProvider<CatalogController>.value(value: _catalog),

        // Serviços sem estado observável entram como Provider simples para que
        // as telas de câmera os obtenham por injeção, não por instanciação.
        Provider<CameraService>.value(value: const DeviceCameraService()),
        Provider<GalleryService>(create: (_) => ImagePickerGalleryService()),
        Provider<SpeciesRepository>.value(value: _deps.speciesRepository),
        Provider<AppDependencies>.value(value: _deps),
      ],
      child: Consumer<SettingsController>(
        builder: (BuildContext context, SettingsController settings, _) {
          return MaterialApp.router(
            title: AppConfig.appName,
            debugShowCheckedModeBanner: false,
            routerConfig: _router,
            themeMode: settings.themeMode,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            builder: (BuildContext context, Widget? child) {
              // Trava a escala de texto numa faixa segura: acima de 1.4 os
              // cabeçalhos quebram o layout em telas pequenas.
              final MediaQueryData mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(
                  textScaler: mq.textScaler.clamp(
                    minScaleFactor: 0.85,
                    maxScaleFactor: 1.4,
                  ),
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
          );
        },
      ),
    );
  }
}
