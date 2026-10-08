import '../models/app_user.dart';

/// Erro de autenticação já traduzido para a linguagem do produto.
///
/// A UI nunca vê `FirebaseAuthException`: a tradução acontece na
/// implementação do repositório, que é o único lugar que conhece o SDK.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Contrato de autenticação.
///
/// Duas implementações, escolhidas por `DATA_SOURCE` em `dependencies.dart`:
/// [MockAuthRepository] (memória) e `FirebaseAuthRepository` (Authentication
/// real). A interface é a mesma, e nenhuma tela sabe qual está em uso.
abstract interface class AuthRepository {
  /// Emite o usuário corrente e `null` quando não há sessão.
  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;

  Future<AppUser> signIn({required String email, required String password});

  /// [privacyVersion] é a versão do aviso de privacidade que a pessoa aceitou
  /// na tela de cadastro. Vem de quem coletou o aceite, e não é preenchido
  /// aqui dentro: um repositório que registrasse aceite por conta própria
  /// gravaria consentimento que ninguém deu.
  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
    String? privacyVersion,
  });

  Future<void> sendPasswordReset(String email);

  Future<void> signOut();

  /// Reenvia o link de confirmação para o e-mail da conta atual.
  ///
  /// Existe por causa do MEDIUM-3 da auditoria: sem confirmação, alguém cadastra
  /// `vitima@exemplo.com` e a vítima perde o endereço para uma conta que não é
  /// dela. E um endereço não confirmado também não serve para recuperar a senha,
  /// o que transforma um esquecimento em perda da conta.
  Future<void> sendEmailVerification();

  /// Recarrega o usuário a partir do servidor.
  ///
  /// Necessário depois de o usuário confirmar o e-mail: a confirmação acontece
  /// **fora** do aplicativo, num navegador, e o objeto em memória não sabe. Sem
  /// recarregar, a tela continuaria pedindo para confirmar algo já confirmado.
  Future<AppUser?> reload();

  /// Confirma a senha de quem já está autenticado.
  ///
  /// # Para que serve
  /// Operações irreversíveis não podem bastar-se num token — ele se renova
  /// sozinho a cada hora, sem pedir senha, e quem pega o aparelho destravado
  /// continua autenticado. O servidor recusa a exclusão de conta quando a claim
  /// `auth_time` do token não é recente, e é isto que move aquela claim.
  ///
  /// O resultado útil não é o retorno, e sim o efeito: depois desta chamada, o
  /// próximo ID token obtido traz `auth_time` novo.
  Future<void> reauthenticate(String password);

  /// O ID token do usuário atual, para as chamadas ao backend.
  ///
  /// [forceRefresh] força uma ida ao servidor — é o que faz o token recém-obtido
  /// carregar o `auth_time` atualizado depois de [reauthenticate]. Sem isso o
  /// SDK devolveria o token em cache, com o `auth_time` antigo, e o servidor
  /// recusaria de novo.
  Future<String?> idToken({bool forceRefresh = false});

  void dispose();
}
