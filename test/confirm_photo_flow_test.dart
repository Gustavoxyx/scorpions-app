import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:scorpions/app/router/app_routes.dart';
import 'package:scorpions/core/theme/app_theme.dart';
import 'package:scorpions/data/mock/mock_species.dart';
import 'package:scorpions/data/models/app_user.dart';
import 'package:scorpions/data/models/captured_image.dart';
import 'package:scorpions/data/models/identification.dart';
import 'package:scorpions/data/repositories/auth_repository.dart';
import 'package:scorpions/data/repositories/identification_repository.dart';
import 'package:scorpions/data/services/connectivity_service.dart';
import 'package:scorpions/data/services/demo_multi_view_service.dart';
import 'package:scorpions/data/services/identification_pipeline.dart';
import 'package:scorpions/data/services/identification_service.dart';
import 'package:scorpions/data/services/image_processing_service.dart';
import 'package:scorpions/data/services/image_upload_service.dart';
import 'package:scorpions/features/camera/confirm_photo_page.dart';
import 'package:scorpions/state/identification_controller.dart';

/// O fluxo de duas fotos, pela tela.
///
/// O controlador tem os próprios testes. Aqui o que está sob teste é o que só
/// existe na interface: que a segunda foto é **oferecida** e não imposta, que
/// voltar da câmera cai na mesma confirmação (e não numa segunda, empilhada),
/// e que a tela cabe num aparelho pequeno nos dois estados.
///
/// A tela de captura de verdade precisa de câmera, permissão e galeria. Aqui
/// ela é substituída por uma página de um botão só, que faz a única coisa que
/// importa para este fluxo: entregar uma foto ao controlador e voltar.
void main() {
  late InMemoryIdentificationRepository repo;
  late IdentificationController controller;

  IdentificationController montarControlador() {
    return IdentificationController(
      service: _ServicoFixo(),
      repository: repo,
      pipeline: IdentificationPipeline(
        auth: _Auth(),
        repository: repo,
        processing: const DefaultImageProcessingService(),
        uploader: const NoopImageUploadService(),
        connectivity: const AlwaysOnlineConnectivityService(),
      ),
      demonstration: true,
      demoFusion: DemoMultiViewService(random: Random(1), disagreementRate: 0),
    );
  }

  Widget app({Brightness brightness = Brightness.light}) {
    final GoRouter router = GoRouter(
      initialLocation: AppRoutes.confirmPhoto,
      routes: <RouteBase>[
        GoRoute(
          path: AppRoutes.home,
          builder: (_, _) => const Scaffold(body: Text('INICIO')),
        ),
        GoRoute(
          path: AppRoutes.confirmPhoto,
          builder: (_, _) => const ConfirmPhotoPage(),
        ),
        GoRoute(
          path: AppRoutes.capture,
          builder: (BuildContext context, _) => _CapturaFalsa(
            controller: context.read<IdentificationController>(),
          ),
        ),
        GoRoute(
          path: AppRoutes.analyzing,
          builder: (_, _) => const Scaffold(body: Text('ANALISANDO')),
        ),
      ],
    );

    return ChangeNotifierProvider<IdentificationController>.value(
      value: controller,
      child: MaterialApp.router(
        theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
        routerConfig: router,
      ),
    );
  }

  setUp(() {
    repo = InMemoryIdentificationRepository(seedWithMockData: false);
    controller = montarControlador();
    controller.stageImage(CapturedImage.simulated());
  });

  /// Toca num botão, rolando até ele antes.
  ///
  /// A tela de confirmação rola quando não cabe — e num teste isso acontece
  /// mais do que num aparelho: a fonte de teste do Flutter desenha todo
  /// caractere como um quadrado da altura da fonte, o que deixa o texto cerca
  /// de duas vezes mais largo, e portanto mais alto, do que a pessoa veria.
  /// Rolar antes de tocar é o que o usuário faria.
  Future<void> tocar(WidgetTester tester, String texto) async {
    await tester.ensureVisible(find.text(texto));
    await tester.pumpAndSettle();
    await tester.tap(find.text(texto));
    await tester.pumpAndSettle();
  }

  void tamanho(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  // ===========================================================================
  // A oferta da segunda foto
  // ===========================================================================

  testWidgets('a segunda foto é OFERECIDA, com o que fotografar',
      (WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Adicionar segunda foto'), findsOneWidget);
    // O convite diz o quê e como ANTES de a pessoa aceitar — "adicionar
    // segunda foto" sozinho não informa que será preciso chegar perto.
    expect(find.text(controller.secondInstruction.description), findsOneWidget);
  });

  testWidgets('seguir com uma foto só é um botão, não um caminho escondido',
      (WidgetTester tester) async {
    // O animal pode ter fugido; a pessoa pode não querer se aproximar. Uma
    // identificação com uma vista vale mais que nenhuma.
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tocar(tester, 'Analisar só esta');

    expect(find.text('ANALISANDO'), findsOneWidget);
    expect(controller.lastResult!.viewCount, 1);
    expect(controller.lastResult!.multiView, isNull);
  });

  // ===========================================================================
  // O caminho de duas fotos, de ponta a ponta
  // ===========================================================================

  testWidgets('adicionar a segunda foto volta para a MESMA confirmação',
      (WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tocar(tester, 'Adicionar segunda foto');

    expect(find.text('CAPTURA'), findsOneWidget);
    expect(controller.isCapturingSecond, isTrue,
        reason: 'a câmera precisa saber que esta é a segunda vista');

    await tocar(tester, 'FOTOGRAFAR');

    // De volta à confirmação, agora com as duas.
    expect(find.text('Duas fotos'), findsOneWidget);
    expect(find.text('Analisar as duas fotos'), findsOneWidget);
    expect(find.byType(ConfirmPhotoPage), findsOneWidget,
        reason: 'uma confirmação só — não uma segunda empilhada sobre a primeira');
    expect(controller.hasSecondView, isTrue,
        reason: 'a segunda foto é inspecionada sozinha ao voltar');
  });

  testWidgets('analisar as duas fotos envia as duas e mostra a fusão',
      (WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tocar(tester, 'Adicionar segunda foto');
    await tocar(tester, 'FOTOGRAFAR');

    await tocar(tester, 'Analisar as duas fotos');

    expect(find.text('ANALISANDO'), findsOneWidget);
    final IdentificationResult r = controller.lastResult!;
    expect(r.viewCount, 2);
    expect(r.multiView, isNotNull);
    expect(r.multiView!.agreeOnTop1, isTrue);
    expect((await repo.fetchHistory()), hasLength(1),
        reason: 'duas fotos, uma identificação');
  });

  testWidgets('"só a 1ª" descarta a segunda e segue', (WidgetTester tester) async {
    // Uma segunda foto que não serviu não pode prender a pessoa.
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tocar(tester, 'Adicionar segunda foto');
    await tocar(tester, 'FOTOGRAFAR');

    await tocar(tester, 'Só a 1ª');

    expect(find.text('ANALISANDO'), findsOneWidget);
    expect(controller.lastResult!.viewCount, 1);
  });

  testWidgets('voltar da câmera sem fotografar mantém a primeira',
      (WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tocar(tester, 'Adicionar segunda foto');

    await tocar(tester, 'DESISTIR');

    expect(find.text('Adicionar segunda foto'), findsOneWidget);
    expect(controller.secondImage, isNull);
    expect(controller.pendingImage, isNotNull);
    expect(controller.isCapturingSecond, isFalse,
        reason: 'senão a primeira foto da PRÓXIMA identificação viraria a '
            'segunda vista desta');
  });

  // ===========================================================================
  // Cabe na tela
  // ===========================================================================

  for (final ({String nome, Size size}) aparelho in <({String nome, Size size})>[
    (nome: 'pequeno 320x568', size: const Size(320, 568)),
    (nome: 'compacto 360x640', size: const Size(360, 640)),
    (nome: 'comum 412x915', size: const Size(412, 915)),
    (nome: 'tablet 768x1024', size: const Size(768, 1024)),
  ]) {
    for (final Brightness tema in Brightness.values) {
      testWidgets(
          'cabe com uma foto — ${aparelho.nome}, tema ${tema.name}',
          (WidgetTester tester) async {
        tamanho(tester, aparelho.size);
        await tester.pumpWidget(app(brightness: tema));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Adicionar segunda foto'), findsOneWidget);
      });

      testWidgets(
          'cabe com duas fotos — ${aparelho.nome}, tema ${tema.name}',
          (WidgetTester tester) async {
        tamanho(tester, aparelho.size);
        await tester.pumpWidget(app(brightness: tema));
        await tester.pumpAndSettle();
        await tocar(tester, 'Adicionar segunda foto');
        await tocar(tester, 'FOTOGRAFAR');

        expect(tester.takeException(), isNull);
        expect(find.text('Analisar as duas fotos'), findsOneWidget);
      });
    }
  }

  testWidgets('cabe com a fonte do sistema ampliada', (WidgetTester tester) async {
    // O caso que uma `Column` com a foto em `Expanded` não aguentaria: a
    // parte de baixo cresce com a fonte e empurra a foto até zero. A tela
    // passa a rolar em vez de transbordar.
    tamanho(tester, const Size(360, 640));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 640),
          textScaler: TextScaler.linear(1.6),
        ),
        child: app(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

// =============================================================================
// Dublês
// =============================================================================

/// O que a tela de captura faz por este fluxo, sem câmera: entrega uma foto ao
/// controlador e volta — ou volta sem entregar nada.
class _CapturaFalsa extends StatelessWidget {
  const _CapturaFalsa({required this.controller});

  final IdentificationController controller;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // A mesma limpeza que a tela de captura de verdade faz ao sair.
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) controller.cancelSecondCapture();
      },
      child: Scaffold(
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('CAPTURA'),
            TextButton(
              onPressed: () {
                controller.stageImage(CapturedImage.simulated());
                context.pop();
              },
              child: const Text('FOTOGRAFAR'),
            ),
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('DESISTIR'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServicoFixo implements IdentificationService {
  @override
  Future<IdentificationResult> identify(
    CapturedImage image, {
    void Function(int stageIndex)? onStage,
    int stageCount = 4,
  }) async {
    return IdentificationResult.identified(
      id: 'mock-fixo',
      image: image,
      isMock: true,
      predictions: <SpeciesPrediction>[
        SpeciesPrediction(species: MockSpecies.tityusSerrulatus, score: 0.90),
        SpeciesPrediction(species: MockSpecies.tityusBahiensis, score: 0.06),
        SpeciesPrediction(species: MockSpecies.tityusStigmurus, score: 0.04),
      ],
    );
  }
}

class _Auth implements AuthRepository {
  @override
  AppUser? get currentUser =>
      const AppUser(id: 'uid-teste', name: 'Teste', email: 't@exemplo.test');

  @override
  Stream<AppUser?> authStateChanges() => throw UnimplementedError();

  @override
  Future<AppUser> signIn({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> sendPasswordReset(String email) => throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();

  @override
  Future<void> sendEmailVerification() => throw UnimplementedError();

  @override
  Future<AppUser?> reload() => throw UnimplementedError();

  @override
  Future<void> reauthenticate(String password) => throw UnimplementedError();

  @override
  Future<String?> idToken({bool forceRefresh = false}) =>
      throw UnimplementedError();

  @override
  void dispose() {}
}
