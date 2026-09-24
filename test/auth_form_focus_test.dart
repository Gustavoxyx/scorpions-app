import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:scorpions/core/constants/app_strings.dart';
import 'package:scorpions/core/theme/app_theme.dart';
import 'package:scorpions/data/repositories/mock_auth_repository.dart';
import 'package:scorpions/features/auth/login_page.dart';
import 'package:scorpions/features/auth/widgets/auth_error_banner.dart';
import 'package:scorpions/state/auth_controller.dart';

/// O formulário de acesso não pode perder o foco quando a tela muda de tamanho
/// por conta própria.
///
/// # O defeito que este teste tranca
/// `LoginPage` monta os filhos com `Reveal.stagger`, que gera uma lista **sem
/// chaves**. O banner de erro entra e sai dessa lista conforme
/// `auth.errorMessage`, deslocando em duas posições tudo o que vem depois.
/// Sem chave, o Flutter reconcilia por posição: os elementos dos campos são
/// descartados e reconstruídos, levando junto o `FocusNode` de cada um.
///
/// Na prática: depois de um login recusado, a primeira tecla digitada na senha
/// dispara `clearError()`, o banner some, o campo é recriado e o foco evapora.
/// O usuário digita e nada mais entra.
void main() {
  Widget harness() {
    return ChangeNotifierProvider<AuthController>(
      create: (_) => AuthController(MockAuthRepository()),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const LoginPage(),
      ),
    );
  }

  testWidgets('a senha continua focada depois que o erro se limpa',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle(); // entradas escalonadas

    final Finder email = find.byType(TextField).first;
    final Finder senha = find.byType(TextField).last;

    // `erro@` é o gatilho de recusa do repositório simulado.
    await tester.enterText(email, 'erro@exemplo.com');
    await tester.enterText(senha, 'errada');
    await tester.pump();

    await tester.tap(find.text(AppStrings.signIn));
    await tester.pumpAndSettle();

    expect(
      find.byType(AuthErrorBanner),
      findsOneWidget,
      reason: 'o cenário exige a tela em estado de erro',
    );

    // O usuário volta ao campo de senha para corrigir.
    await tester.showKeyboard(senha);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).focusNode?.hasFocus,
      isTrue,
      reason: 'tocar no campo deve focá-lo',
    );

    // Primeira tecla: o `onChanged` chama `clearError()` e o banner sai da
    // árvore. É exatamente aqui que o foco se perdia.
    await tester.enterText(senha, 'n');
    await tester.pumpAndSettle();

    expect(find.byType(AuthErrorBanner), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).focusNode?.hasFocus,
      isTrue,
      reason: 'sair o banner não pode tirar o foco de quem está digitando',
    );
  });
}
