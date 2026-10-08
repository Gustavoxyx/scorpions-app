import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/app_user.dart';
import '../data/repositories/auth_repository.dart';
import '../data/services/failure.dart';

/// Estados possíveis da autenticação.
///
/// São classes seladas em vez de booleanos porque o roteador precisa
/// distinguir "ainda não sei" de "não autenticado" — sem isso, o app pisca a
/// tela de login durante a restauração de sessão da Fase 3.
sealed class AuthState {
  const AuthState();
}

/// Sessão ainda sendo restaurada. Estado inicial.
class AuthUnknown extends AuthState {
  const AuthUnknown();
}

/// Operação em andamento (login, cadastro, logout).
class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);
  final AppUser user;
}

class AuthError extends AuthState {
  const AuthError(this.message);
  final String message;
}

/// Orquestra a autenticação para a UI.
///
/// Não conhece Firebase nem nenhum SDK: fala apenas com [AuthRepository].
/// Trocar a implementação do repositório na Fase 3 não altera este arquivo.
class AuthController extends ChangeNotifier {
  AuthController(this._repository) {
    _subscription = _repository.authStateChanges().listen(_onUserChanged);
  }

  final AuthRepository _repository;
  late final StreamSubscription<AppUser?> _subscription;

  AuthState _state = const AuthUnknown();
  AuthState get state => _state;

  AppUser? get user => switch (_state) {
        AuthAuthenticated(user: final AppUser u) => u,
        _ => null,
      };

  bool get isAuthenticated => _state is AuthAuthenticated;
  bool get isResolving => _state is AuthUnknown;
  bool get isBusy => _state is AuthLoading;

  String? get errorMessage =>
      _state is AuthError ? (_state as AuthError).message : null;

  Future<void> signIn({required String email, required String password}) {
    return _run(() => _repository.signIn(email: email, password: password));
  }

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
    String? privacyVersion,
  }) {
    return _run(
      () => _repository.signUp(
        name: name,
        email: email,
        password: password,
        privacyVersion: privacyVersion,
      ),
    );
  }

  Future<bool> sendPasswordReset(String email) async {
    if (isBusy) return false;
    _set(const AuthLoading());
    try {
      await _repository.sendPasswordReset(email);
      _set(const AuthUnauthenticated());
      return true;
    } on AppFailure catch (e) {
      _set(AuthError(e.message));
      return false;
    } on AuthFailure catch (e) {
      _set(AuthError(e.message));
      return false;
    } catch (_) {
      _set(const AuthError('Não foi possível enviar o link. Tente de novo.'));
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _repository.signOut();
    } catch (_) {
      // Encerrar sessão nunca pode falhar do ponto de vista do usuário: se o
      // servidor não responder, a sessão local é descartada mesmo assim e o
      // roteador leva de volta ao login.
      _set(const AuthUnauthenticated());
    }
  }

  /// Reenvia o link de confirmação do e-mail (MEDIUM-3 da auditoria).
  ///
  /// Devolve se o envio aconteceu. Não muda o estado de autenticação: a pessoa
  /// continua dentro do aplicativo enquanto o e-mail não é confirmado. Bloquear
  /// o uso por isso puniria quem ainda não abriu a caixa de entrada — e o risco
  /// real do endereço não confirmado está na recuperação de senha, não no uso.
  Future<bool> sendEmailVerification() async {
    try {
      await _repository.sendEmailVerification();
      return true;
    } on AppFailure catch (e) {
      _set(AuthError(e.message));
      return false;
    } catch (_) {
      _set(const AuthError('Não foi possível enviar o link. Tente de novo.'));
      return false;
    }
  }

  /// Recarrega o usuário do servidor, para saber se o e-mail já foi confirmado.
  ///
  /// A confirmação acontece **fora** do aplicativo, num navegador, e o objeto em
  /// memória não sabe. Sem isto, o aviso continuaria na tela depois de
  /// confirmado — e um aviso que não some ensina o usuário a ignorar avisos.
  Future<void> reloadUser() async {
    try {
      final AppUser? atualizado = await _repository.reload();
      if (atualizado != null) _set(AuthAuthenticated(atualizado));
    } catch (_) {
      // Falhar aqui não merece mensagem: o usuário pediu uma verificação, não
      // uma operação. O aviso simplesmente continua na tela.
    }
  }

  /// Confirma a senha de quem já está autenticado, para operação irreversível.
  ///
  /// Repassa a falha em vez de engolir: quem chama é o fluxo de exclusão de
  /// conta, que precisa distinguir "senha errada" de "deu outro problema".
  Future<void> reauthenticate(String password) =>
      _repository.reauthenticate(password);

  /// O ID token, para as chamadas ao backend.
  Future<String?> idToken({bool forceRefresh = false}) =>
      _repository.idToken(forceRefresh: forceRefresh);

  /// Limpa a mensagem de erro quando o usuário volta a editar o formulário.
  void clearError() {
    if (_state is AuthError) _set(const AuthUnauthenticated());
  }

  Future<void> _run(Future<AppUser> Function() action) async {
    // Bloqueia reentrada: sem isto, tocar duas vezes em "Entrar" dispara dois
    // pedidos e o segundo pode sobrescrever o resultado do primeiro (§26).
    if (isBusy) return;

    _set(const AuthLoading());
    try {
      await action();
      // O estado autenticado chega pelo stream do repositório, mantendo uma
      // única fonte de verdade.
    } on AppFailure catch (e) {
      // Já traduzido pelo `FirebaseErrorMapper`; a tela nunca vê código de SDK.
      _set(AuthError(e.message));
    } on AuthFailure catch (e) {
      // Caminho do repositório simulado.
      _set(AuthError(e.message));
    } catch (_) {
      _set(const AuthError('Não foi possível concluir. Tente novamente.'));
    }
  }

  void _onUserChanged(AppUser? user) {
    _set(user == null ? const AuthUnauthenticated() : AuthAuthenticated(user));
  }

  void _set(AuthState next) {
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription.cancel();
    _repository.dispose();
    super.dispose();
  }
}
