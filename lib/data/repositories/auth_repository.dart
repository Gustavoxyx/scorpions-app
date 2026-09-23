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
/// Fase 1: [MockAuthRepository] (memória).
/// Fase 3: `FirebaseAuthRepository` implementando esta mesma interface.
abstract interface class AuthRepository {
  /// Emite o usuário corrente e `null` quando não há sessão.
  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;

  Future<AppUser> signIn({required String email, required String password});

  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
  });

  Future<void> sendPasswordReset(String email);

  Future<void> signOut();

  void dispose();
}
