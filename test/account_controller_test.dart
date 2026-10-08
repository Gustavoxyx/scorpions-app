import 'package:flutter_test/flutter_test.dart';
import 'package:scorpions/core/constants/app_environment.dart';
import 'package:scorpions/data/models/app_user.dart';
import 'package:scorpions/data/repositories/account_repository.dart';
import 'package:scorpions/data/repositories/auth_repository.dart';
import 'package:scorpions/data/services/backend_client.dart';
import 'package:scorpions/data/services/failure.dart';
import 'package:scorpions/state/account_controller.dart';

/// Testes do fluxo de exclusão e exportação de conta.
///
/// O que está sob teste é o **fluxo de dois passos**: o servidor recusa pedindo
/// a senha, a tela coleta, o controlador reautentica e tenta de novo. É onde
/// mora a complexidade, e é onde um erro deixaria o usuário preso num pedido de
/// senha que não termina.
void main() {
  group('AppEnvironmentConfig.isUrlSafe — a guarda de TLS (C-3)', () {
    test('aceita https em qualquer host', () {
      expect(AppEnvironmentConfig.isUrlSafe('https://api.exemplo.com'), isTrue);
      expect(AppEnvironmentConfig.isUrlSafe('https://localhost:8000'), isTrue);
    });

    test('aceita http apenas em localhost', () {
      // Desenvolvimento local não tem rede para interceptar.
      expect(AppEnvironmentConfig.isUrlSafe('http://localhost:8000'), isTrue);
      expect(AppEnvironmentConfig.isUrlSafe('http://127.0.0.1:8000'), isTrue);
      expect(AppEnvironmentConfig.isUrlSafe('http://[::1]:8000'), isTrue);
    });

    test('RECUSA http em endereço de rede local', () {
      // O caso que mais parece inofensivo e não é: num Wi-Fi compartilhado,
      // qualquer outro aparelho vê o tráfego — e o que atravessa é o ID token
      // do usuário.
      expect(AppEnvironmentConfig.isUrlSafe('http://192.168.0.10:8000'), isFalse);
      expect(AppEnvironmentConfig.isUrlSafe('http://10.0.0.5:8000'), isFalse);
      expect(AppEnvironmentConfig.isUrlSafe('http://meu-pc.local:8000'), isFalse);
    });

    test('RECUSA http em host remoto', () {
      expect(AppEnvironmentConfig.isUrlSafe('http://api.exemplo.com'), isFalse);
    });

    test('recusa o que não é http nem https', () {
      for (final String url in <String>[
        '',
        'api.exemplo.com',
        'ftp://exemplo.com',
        'ws://exemplo.com',
        'javascript:alert(1)',
        'file:///etc/passwd',
      ]) {
        expect(
          AppEnvironmentConfig.isUrlSafe(url),
          isFalse,
          reason: 'aceitou "$url"',
        );
      }
    });

    test('não se engana com localhost no meio do endereço', () {
      // `http://evil.com/localhost` e `http://localhost.evil.com` não são
      // localhost. O primeiro tem o nome no caminho; o segundo, como
      // subdomínio.
      expect(
        AppEnvironmentConfig.isUrlSafe('http://evil.com/localhost'),
        isFalse,
      );
      expect(
        AppEnvironmentConfig.isUrlSafe('http://localhost.evil.com'),
        isFalse,
      );
    });

    test('RECUSA localhost disfarçado de usuário e senha', () {
      // O defeito que a primeira versão desta função tinha.
      //
      // Em `http://localhost:80@evil.com`, o host é `evil.com`: `localhost:80`
      // é usuário e senha. Extrair o host cortando a string no primeiro `:`
      // devolvia `localhost`, e o token do usuário iria em texto claro para um
      // host de terceiro. Só apareceu porque o teste do IPv6 falhou e obrigou a
      // reler o analisador.
      for (final String url in <String>[
        'http://localhost:80@evil.com',
        'http://localhost@evil.com',
        'http://127.0.0.1:8000@evil.com/v1',
        'http://localhost:senha@192.168.0.10:8000',
      ]) {
        expect(
          AppEnvironmentConfig.isUrlSafe(url),
          isFalse,
          reason: 'aceitou "$url", cujo host real não é local',
        );
      }
    });

    test('recusa credencial embutida mesmo em https', () {
      // O backend autentica por cabeçalho. Usuário e senha no endereço não têm
      // uso legítimo aqui, e acabariam em log de proxy e de servidor.
      expect(
        AppEnvironmentConfig.isUrlSafe('https://usuario:senha@api.exemplo.com'),
        isFalse,
      );
    });

    test('recusa endereço sem host', () {
      expect(AppEnvironmentConfig.isUrlSafe('https://'), isFalse);
      expect(AppEnvironmentConfig.isUrlSafe('http:///caminho'), isFalse);
    });
  });

  group('UnavailableAccountRepository', () {
    const UnavailableAccountRepository repo = UnavailableAccountRepository();

    test('NUNCA finge que apagou', () async {
      // A pior coisa que este dublê poderia fazer: devolver um recibo. O
      // usuário acreditaria que os dados dele foram embora.
      await expectLater(repo.deleteAccount(), throwsA(isA<AppFailure>()));
    });

    test('falha dizendo o motivo', () async {
      try {
        await repo.deleteAccount();
        fail('deveria ter falhado');
      } on AppFailure catch (erro) {
        expect(erro.code, 'backend_not_configured');
        expect(erro.message, isNotEmpty);
      }
    });

    test('a cota devolve nulo em vez de falhar', () async {
      // Saber a cota é conveniência. Uma tela que não abre porque não conseguiu
      // ler um contador é pior que uma tela sem o contador.
      expect(await repo.quota(), isNull);
    });
  });

  group('AccountController — exclusão em dois passos', () {
    test('o caminho normal pede a senha antes de apagar', () async {
      final _ContaFalsa conta = _ContaFalsa(exigeReauth: true);
      final _AuthFalso auth = _AuthFalso();
      final AccountController c =
          AccountController(account: conta, auth: auth);

      await c.requestDeletion();

      expect(c.stage, DeletionStage.awaitingPassword);
      // Não é erro: é o próximo passo. Virar `failure` faria a tela mostrar
      // vermelho onde deveria abrir um campo de senha.
      expect(c.failure, isNull);
      expect(conta.tentativas, 1);
    });

    test('com a senha certa, apaga e devolve o recibo', () async {
      final _ContaFalsa conta = _ContaFalsa(exigeReauth: true);
      final _AuthFalso auth = _AuthFalso(senhaCorreta: 'senha-boa');
      final AccountController c =
          AccountController(account: conta, auth: auth);

      await c.requestDeletion();
      conta.exigeReauth = false; // o servidor aceita depois da reautenticação
      await c.confirmDeletion('senha-boa');

      expect(c.stage, DeletionStage.done);
      expect(c.receipt?.images, 3);
      expect(c.receipt?.identifications, 2);
    });

    test('força a renovação do token depois de reautenticar', () async {
      // O detalhe que, esquecido, prenderia o usuário num laço: reautenticar
      // move a claim `auth_time`, mas o SDK continua entregando o token em
      // cache, com o valor antigo. O servidor recusaria de novo, e o pedido de
      // senha apareceria uma segunda vez depois da senha certa.
      final _ContaFalsa conta = _ContaFalsa(exigeReauth: true);
      final _AuthFalso auth = _AuthFalso(senhaCorreta: 'x');
      final AccountController c =
          AccountController(account: conta, auth: auth);

      await c.requestDeletion();
      conta.exigeReauth = false;
      await c.confirmDeletion('x');

      expect(
        auth.pedidosDeTokenForcado,
        1,
        reason: 'o token precisa ser renovado à força depois de reautenticar',
      );
    });

    test('senha errada volta ao pedido de senha, não ao início', () async {
      // Mandar o usuário recomeçar o fluxo seria punição por erro de digitação.
      final _ContaFalsa conta = _ContaFalsa(exigeReauth: true);
      final _AuthFalso auth = _AuthFalso(senhaCorreta: 'certa');
      final AccountController c =
          AccountController(account: conta, auth: auth);

      await c.requestDeletion();
      await c.confirmDeletion('errada');

      expect(c.stage, DeletionStage.awaitingPassword);
      expect(c.failure?.code, 'wrong-password');
    });

    test('se o servidor insistir em pedir senha, explica a causa provável',
        () async {
      // Token renovado e o servidor ainda recusa: é relógio fora de hora no
      // aparelho, quase sempre. Repetir o pedido de senha deixaria o usuário
      // num laço sem saída e sem explicação.
      final _ContaFalsa conta = _ContaFalsa(exigeReauth: true);
      final _AuthFalso auth = _AuthFalso(senhaCorreta: 'x');
      final AccountController c =
          AccountController(account: conta, auth: auth);

      await c.requestDeletion();
      await c.confirmDeletion('x'); // `exigeReauth` continua true

      expect(c.stage, DeletionStage.idle);
      expect(c.failure?.code, 'reauth_loop');
      expect(c.failure!.message.toLowerCase(), contains('hora'));
    });

    test('falha que não é de senha não pede senha', () async {
      final _ContaFalsa conta = _ContaFalsa(
        erro: const AppFailure(
          kind: FailureKind.network,
          message: 'Sem conexão.',
          code: 'offline',
        ),
      );
      final AccountController c =
          AccountController(account: conta, auth: _AuthFalso());

      await c.requestDeletion();

      expect(c.stage, DeletionStage.idle);
      expect(c.failure?.code, 'offline');
    });

    test('cancelar volta ao início', () async {
      final _ContaFalsa conta = _ContaFalsa(exigeReauth: true);
      final AccountController c =
          AccountController(account: conta, auth: _AuthFalso());

      await c.requestDeletion();
      c.cancelDeletion();

      expect(c.stage, DeletionStage.idle);
      expect(c.failure, isNull);
    });

    test('cancelar NÃO desfaz uma exclusão concluída', () async {
      // Voltar de `done` para `idle` mostraria a tela de exclusão de novo, para
      // uma conta que já não existe.
      final _ContaFalsa conta = _ContaFalsa();
      final AccountController c =
          AccountController(account: conta, auth: _AuthFalso());

      await c.requestDeletion();
      expect(c.stage, DeletionStage.done);

      c.cancelDeletion();
      expect(c.stage, DeletionStage.done);
    });

    test('não aceita confirmar senha fora do momento certo', () async {
      final _ContaFalsa conta = _ContaFalsa();
      final AccountController c =
          AccountController(account: conta, auth: _AuthFalso());

      await c.confirmDeletion('qualquer');

      expect(c.stage, DeletionStage.idle);
      expect(conta.tentativas, 0, reason: 'não deveria ter chamado o servidor');
    });

    test('bloqueia reentrada enquanto apaga', () async {
      // Dois toques no botão disparariam duas cascatas. A segunda encontraria
      // metade dos dados já apagados e falharia por um motivo inventado.
      final _ContaFalsa conta = _ContaFalsa(demora: true);
      final AccountController c =
          AccountController(account: conta, auth: _AuthFalso());

      final Future<void> primeira = c.requestDeletion();
      await c.requestDeletion(); // ignorada
      await primeira;

      expect(conta.tentativas, 1);
    });
  });

  group('AccountController — exportação', () {
    test('devolve o pacote', () async {
      final _ContaFalsa conta = _ContaFalsa();
      final AccountController c =
          AccountController(account: conta, auth: _AuthFalso());

      final Map<String, Object?>? pacote = await c.exportData();

      expect(pacote, isNotNull);
      expect(pacote!['profile'], isNotNull);
    });

    test('em caso de falha devolve nulo e registra o motivo', () async {
      final _ContaFalsa conta = _ContaFalsa(
        erro: const AppFailure(
          kind: FailureKind.network,
          message: 'Sem conexão.',
          code: 'offline',
        ),
      );
      final AccountController c =
          AccountController(account: conta, auth: _AuthFalso());

      expect(await c.exportData(), isNull);
      expect(c.failure?.code, 'offline');
      expect(c.isExporting, isFalse, reason: 'o estado precisa ser limpo');
    });
  });

  group('QuotaSnapshot', () {
    test('avisa quando está acabando, não quando acabou', () {
      // Descobrir o limite depois de enquadrar o animal, focar e disparar é
      // descobrir tarde: a foto já foi tirada e não serve para nada.
      expect(const QuotaSnapshot(used: 55, limit: 60).isLow, isTrue);
      expect(const QuotaSnapshot(used: 30, limit: 60).isLow, isFalse);
    });

    test('esgotada não é "acabando"', () {
      const QuotaSnapshot cheia = QuotaSnapshot(used: 60, limit: 60);
      expect(cheia.exhausted, isTrue);
      expect(cheia.isLow, isFalse, reason: 'são avisos diferentes');
      expect(cheia.remaining, 0);
    });

    test('nunca devolve restante negativo', () {
      expect(const QuotaSnapshot(used: 70, limit: 60).remaining, 0);
    });
  });

  group('BackendResponse', () {
    test('reconhece o pedido de reautenticação pelo cabeçalho', () {
      // 401 com este cabeçalho significa "reautentique"; 401 sem ele significa
      // "entre de novo". Confundir os dois faria o usuário sair da conta sem
      // precisar.
      const BackendResponse comReauth = BackendResponse(
        statusCode: 401,
        body: <String, Object?>{},
        headers: <String, String>{'x-reauth-required': 'true'},
      );
      const BackendResponse semReauth = BackendResponse(
        statusCode: 401,
        body: <String, Object?>{},
      );

      expect(comReauth.needsReauth, isTrue);
      expect(semReauth.needsReauth, isFalse);
    });

    test('extrai a mensagem que o servidor quis mostrar', () {
      const BackendResponse r = BackendResponse(
        statusCode: 429,
        body: <String, Object?>{'detail': 'Você atingiu o limite.'},
      );
      expect(r.detail, 'Você atingiu o limite.');
    });

    test('detalhe vazio ou de outro tipo não vira mensagem', () {
      expect(
        const BackendResponse(statusCode: 500, body: <String, Object?>{'detail': ''})
            .detail,
        isNull,
      );
      expect(
        const BackendResponse(
          statusCode: 500,
          body: <String, Object?>{'detail': 42},
        ).detail,
        isNull,
      );
    });
  });
}

// =============================================================================
// Dublês
// =============================================================================

class _ContaFalsa implements AccountRepository {
  _ContaFalsa({
    this.exigeReauth = false,
    this.erro,
    this.demora = false,
  });

  bool exigeReauth;
  final AppFailure? erro;
  final bool demora;
  int tentativas = 0;

  @override
  Future<DeletionReceipt> deleteAccount() async {
    tentativas++;
    if (demora) await Future<void>.delayed(const Duration(milliseconds: 20));
    if (erro != null) throw erro!;
    if (exigeReauth) throw const ReauthenticationRequired();
    return const DeletionReceipt(images: 3, identifications: 2);
  }

  @override
  Future<Map<String, Object?>> exportData() async {
    if (erro != null) throw erro!;
    return <String, Object?>{
      'profile': <String, Object?>{'name': 'Teste'},
      'identifications': <Object?>[],
    };
  }

  @override
  Future<QuotaSnapshot?> quota() async =>
      const QuotaSnapshot(used: 5, limit: 60);
}

class _AuthFalso implements AuthRepository {
  _AuthFalso({this.senhaCorreta});

  final String? senhaCorreta;
  int pedidosDeTokenForcado = 0;

  @override
  Future<void> reauthenticate(String password) async {
    if (senhaCorreta != null && password != senhaCorreta) {
      throw const AppFailure(
        kind: FailureKind.authentication,
        message: 'Senha incorreta.',
        code: 'wrong-password',
      );
    }
  }

  @override
  Future<String?> idToken({bool forceRefresh = false}) async {
    if (forceRefresh) pedidosDeTokenForcado++;
    return 'token';
  }

  // O resto da interface não participa deste fluxo. Lançar em vez de devolver
  // um valor plausível é deliberado: se o controlador passar a usá-los, o teste
  // quebra e diz onde.
  @override
  Stream<AppUser?> authStateChanges() => throw UnimplementedError();

  @override
  AppUser? get currentUser => throw UnimplementedError();

  @override
  Future<AppUser> signIn({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
    String? privacyVersion,
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
  void dispose() {}
}
