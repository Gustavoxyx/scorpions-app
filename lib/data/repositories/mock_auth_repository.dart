import 'dart:async';

import '../../core/constants/app_config.dart';
import '../models/app_user.dart';
import 'auth_repository.dart';

/// ============================================================================
/// DADOS SIMULADOS — FASE 1
/// ============================================================================
/// Autenticação em memória. Aceita qualquer e-mail válido e qualquer senha com
/// o tamanho mínimo, porque não existe backend: o objetivo é exercitar os
/// estados da tela, não validar credenciais.
///
/// SEGURANÇA: nada é persistido, nenhuma senha é armazenada nem comparada, e
/// não há credencial embutida no código. Ao trocar por Firebase na Fase 3, a
/// verificação passa a acontecer no servidor — como deve ser.
/// ============================================================================
class MockAuthRepository implements AuthRepository {
  MockAuthRepository() {
    if (AppConfig.demoAutoLogin) _current = _demoUser();
  }

  final StreamController<AppUser?> _controller =
      StreamController<AppUser?>.broadcast();

  AppUser? _current;

  /// Usuário fictício usado quando `DEMO_AUTOLOGIN` está ligado.
  static AppUser _demoUser() => AppUser(
        id: 'demo-user',
        name: 'Gustavo Nunes',
        email: 'demo@scorpions.app',
        identificationCount: 4,
        speciesSeenCount: 3,
        memberSince: DateTime.now().subtract(const Duration(days: 96)),
      );

  /// Latência artificial para que os estados de carregamento sejam visíveis.
  static const Duration _latency = Duration(milliseconds: 900);

  @override
  AppUser? get currentUser => _current;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(_latency);
    final String normalized = email.trim().toLowerCase();

    // Gatilho de demonstração para exercitar o estado de erro da tela.
    if (normalized.startsWith('erro@')) {
      throw const AuthFailure('E-mail ou senha incorretos.');
    }

    final AppUser user = AppUser(
      id: 'mock-user',
      name: _nameFromEmail(normalized),
      email: normalized,
      identificationCount: 4,
      speciesSeenCount: 3,
      memberSince: DateTime.now().subtract(const Duration(days: 96)),
    );
    _emit(user);
    return user;
  }

  @override
  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(_latency);
    final AppUser user = AppUser(
      id: 'mock-user',
      name: name.trim(),
      email: email.trim().toLowerCase(),
      memberSince: DateTime.now(),
    );
    _emit(user);
    return user;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await Future<void>.delayed(_latency);
  }

  @override
  Future<void> signOut() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _emit(null);
  }

  @override
  void dispose() => _controller.close();

  void _emit(AppUser? user) {
    _current = user;
    if (!_controller.isClosed) _controller.add(user);
  }

  /// Deriva um nome apresentável a partir do e-mail, só para a demonstração.
  static String _nameFromEmail(String email) {
    final String local = email.split('@').first.replaceAll(RegExp(r'[._-]+'), ' ');
    return local
        .split(' ')
        .where((String p) => p.isNotEmpty)
        .map((String p) => p[0].toUpperCase() + p.substring(1))
        .join(' ');
  }
}
