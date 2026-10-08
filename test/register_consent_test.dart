import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:scorpions/app/dependencies.dart';
import 'package:scorpions/core/constants/legal_documents.dart';
import 'package:scorpions/core/theme/app_theme.dart';
import 'package:scorpions/data/models/app_user.dart';
import 'package:scorpions/data/repositories/auth_repository.dart';
import 'package:scorpions/features/auth/register_page.dart';
import 'package:scorpions/features/legal/legal_document_page.dart';
import 'package:scorpions/state/auth_controller.dart';

/// Registra o que a tela de cadastro pediu ao repositório.
class _AuthQueRegistra implements AuthRepository {
  final List<String?> versoesAceitas = <String?>[];

  @override
  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
    String? privacyVersion,
  }) async {
    versoesAceitas.add(privacyVersion);
    return AppUser(id: 'u1', name: name, email: email);
  }

  @override
  Stream<AppUser?> authStateChanges() => Stream<AppUser?>.value(null);

  @override
  AppUser? get currentUser => null;

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late _AuthQueRegistra repo;

  Future<void> abrir(WidgetTester tester) async {
    repo = _AuthQueRegistra();
    final AuthController auth = AuthController(repo);
    addTearDown(auth.dispose);

    final GoRouter router = GoRouter(
      initialLocation: '/register',
      routes: <RouteBase>[
        GoRoute(
          path: '/register',
          builder: (BuildContext c, GoRouterState s) => const RegisterPage(),
        ),
        GoRoute(
          path: '/legal/privacy',
          builder: (BuildContext c, GoRouterState s) =>
              const LegalDocumentPage(document: LegalDocuments.privacy),
        ),
      ],
    );
    addTearDown(router.dispose);

    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: <ChangeNotifierProvider<dynamic>>[
          ChangeNotifierProvider<AuthController>.value(value: auth),
        ],
        child: Provider<AppDependencies>.value(
          value: AppDependencies.mock(),
          child: MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.light(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> preencher(WidgetTester tester) async {
    await tester.enterText(
        find.byKey(const ValueKey<String>('cadastro-nome')), 'Ana Lima');
    await tester.enterText(
        find.byKey(const ValueKey<String>('cadastro-email')), 'ana@exemplo.com');
    await tester.enterText(
        find.byKey(const ValueKey<String>('cadastro-senha')), 'senha-longa-1');
    await tester.enterText(
        find.byKey(const ValueKey<String>('cadastro-confirmar')), 'senha-longa-1');
  }

  Future<void> criarConta(WidgetTester tester) async {
    final Finder botao = find.text('Criar conta').last;
    await tester.ensureVisible(botao);
    await tester.tap(botao);
    // Quadros contados, e não `pumpAndSettle`: depois de um cadastro aceito o
    // botão fica em carregamento até a sessão chegar, e o dublê deste teste
    // nunca a emite.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('sem aceitar o aviso, a conta não é criada', (
    WidgetTester tester,
  ) async {
    await abrir(tester);
    await preencher(tester);

    await criarConta(tester);

    expect(repo.versoesAceitas, isEmpty);
    expect(
      find.text('Para criar a conta é preciso ler e aceitar o aviso.'),
      findsOneWidget,
    );
  });

  testWidgets('com o aceite, o cadastro registra QUAL versão foi aceita', (
    WidgetTester tester,
  ) async {
    await abrir(tester);
    await preencher(tester);
    final Finder aceite = find.byKey(const ValueKey<String>('cadastro-aceite'));
    await tester.ensureVisible(aceite);
    await tester.tap(aceite);
    await tester.pump();

    await criarConta(tester);

    expect(repo.versoesAceitas, <String?>[LegalDocuments.privacyVersion]);
  });

  testWidgets('o aviso pode ser lido antes de aceitar', (
    WidgetTester tester,
  ) async {
    await abrir(tester);
    final Finder ler = find.byKey(const ValueKey<String>('cadastro-ler-aviso'));
    await tester.ensureVisible(ler);

    await tester.tap(ler);
    await tester.pumpAndSettle();

    expect(find.text('Aviso de privacidade'), findsWidgets);
    expect(find.text('O que coletamos'), findsOneWidget);
  });

  testWidgets('a cobrança do aceite só aparece depois de uma tentativa', (
    WidgetTester tester,
  ) async {
    await abrir(tester);

    expect(
      find.text('Para criar a conta é preciso ler e aceitar o aviso.'),
      findsNothing,
    );
  });
}
