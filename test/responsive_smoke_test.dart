import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:scorpions/core/theme/app_theme.dart';
import 'package:scorpions/data/mock/mock_history.dart';
import 'package:scorpions/data/mock/mock_species.dart';
import 'package:scorpions/data/models/identification.dart';
import 'package:scorpions/data/repositories/identification_repository.dart';
import 'package:scorpions/data/repositories/mock_auth_repository.dart';
import 'package:scorpions/data/repositories/species_repository.dart';
import 'package:scorpions/features/auth/login_page.dart';
import 'package:scorpions/features/auth/register_page.dart';
import 'package:scorpions/features/catalog/catalog_page.dart';
import 'package:scorpions/features/history/history_page.dart';
import 'package:scorpions/features/home/home_page.dart';
import 'package:scorpions/features/home/photo_tips_page.dart';
import 'package:scorpions/features/identification/result_page.dart';
import 'package:scorpions/features/identification/unidentified_page.dart';
import 'package:scorpions/features/onboarding/onboarding_page.dart';
import 'package:scorpions/features/profile/profile_page.dart';
import 'package:scorpions/features/settings/settings_page.dart';
import 'package:scorpions/features/species/species_detail_page.dart';
import 'package:scorpions/state/auth_controller.dart';
import 'package:scorpions/state/catalog_controller.dart';
import 'package:scorpions/state/history_controller.dart';
import 'package:scorpions/state/identification_controller.dart';
import 'package:scorpions/state/onboarding_controller.dart';
import 'package:scorpions/state/settings_controller.dart';
import 'package:scorpions/data/services/identification_service.dart';

/// Verificação de responsividade e integridade de layout.
///
/// # Por que este teste existe
/// O produto é mobile e roda em telas muito diferentes (§33). Um `RenderFlex
/// overflow` não quebra o build — ele só aparece como uma faixa listrada em
/// tempo de execução, e em build de release some silenciosamente. Este teste
/// monta cada tela em quatro larguras e falha se **qualquer** exceção de layout
/// for lançada.
///
/// Ele substitui o `widget_test.dart` gerado pelo `flutter create`, que ainda
/// testava o aplicativo de contador do template e falhava desde a Fase 1.
void main() {
  /// Larguras representativas do parque de aparelhos alvo.
  const Map<String, Size> viewports = <String, Size>{
    'Android pequeno (320)': Size(320, 640),
    'Android comum (360)': Size(360, 740),
    'iPhone (390)': Size(390, 844),
    'Tablet (768)': Size(768, 1024),
  };

  /// Monta uma tela isolada com todas as dependências que ela observa.
  Widget harness(Widget screen, {required Brightness brightness}) {
    final IdentificationRepository identifications =
        InMemoryIdentificationRepository();

    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<AuthController>(
          create: (_) => AuthController(MockAuthRepository()),
        ),
        ChangeNotifierProvider<OnboardingController>(
          create: (_) => OnboardingController(),
        ),
        ChangeNotifierProvider<SettingsController>(
          create: (_) => SettingsController(),
        ),
        ChangeNotifierProvider<IdentificationController>(
          create: (_) => IdentificationController(
            service: MockIdentificationService(),
            repository: identifications,
          ),
        ),
        ChangeNotifierProvider<HistoryController>(
          create: (_) => HistoryController(identifications),
        ),
        ChangeNotifierProvider<CatalogController>(
          create: (_) => CatalogController(const MockSpeciesRepository()),
        ),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
        home: screen,
      ),
    );
  }

  /// Constrói a tela, deixa as animações de entrada terminarem e verifica que
  /// nenhuma exceção de layout foi lançada.
  Future<void> expectNoLayoutIssues(
    WidgetTester tester,
    Widget screen, {
    required Size size,
    required Brightness brightness,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(screen, brightness: brightness));

    // As telas usam entradas escalonadas; sem avançar o relógio o teste
    // observaria apenas o primeiro quadro.
    //
    // `pumpAndSettle` e não dois `pump` de duração fixa: um `RenderFlex` só
    // reporta transbordo quando é pintado, e `Reveal` mantém os itens em
    // opacidade zero até a vez de cada um chegar. Com quadros avulsos, os
    // últimos itens da lista podiam nunca ser pintados dentro da janela
    // observada — foi assim que um transbordo de 60px na tela de acesso
    // passou despercebido por toda a Fase 2.
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: 'Layout quebrou em ${size.width.toInt()}x${size.height.toInt()} '
          '(${brightness.name})',
    );
  }

  /// Telas que podem ser montadas isoladamente, sem rota ativa.
  Map<String, Widget> screens() {
    final IdentificationResult identified = MockHistory.seed()
        .firstWhere((IdentificationResult r) => !r.isRejected);

    return <String, Widget>{
      'Onboarding': const OnboardingPage(),
      'Login': const LoginPage(),
      'Cadastro': const RegisterPage(),
      'Home': const HomePage(),
      'Histórico': const HistoryPage(),
      'Catálogo': const CatalogPage(),
      'Perfil': const ProfilePage(),
      'Configurações': const SettingsPage(),
      'Dicas de foto': const PhotoTipsPage(),
      'Ficha da espécie': SpeciesDetailPage(
        speciesId: MockSpecies.tityusSerrulatus.id,
        preloaded: MockSpecies.tityusSerrulatus,
      ),
      // As telas de resultado leem o controlador; aqui basta garantir que o
      // caminho "sem resultado" também se comporte.
      'Resultado (vazio)': const ResultPage(),
      'Não identificado (vazio)': const UnidentifiedPage(),
      // Mantém a referência viva para documentar o dado usado acima.
      if (identified.predictions.isEmpty) 'nunca': const SizedBox.shrink(),
    };
  }

  for (final MapEntry<String, Size> viewport in viewports.entries) {
    group(viewport.key, () {
      for (final MapEntry<String, Widget> screen in screens().entries) {
        testWidgets('${screen.key} — tema claro', (WidgetTester tester) async {
          await expectNoLayoutIssues(
            tester,
            screen.value,
            size: viewport.value,
            brightness: Brightness.light,
          );
        });
      }
    });
  }

  group('Paridade do tema escuro (360dp)', () {
    for (final MapEntry<String, Widget> screen in screens().entries) {
      testWidgets('${screen.key} — tema escuro', (WidgetTester tester) async {
        await expectNoLayoutIssues(
          tester,
          screen.value,
          size: const Size(360, 740),
          brightness: Brightness.dark,
        );
      });
    }
  });
}
