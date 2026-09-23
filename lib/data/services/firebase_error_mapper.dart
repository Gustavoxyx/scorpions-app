import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'failure.dart';

/// Traduz exceções do Firebase para [AppFailure] (brief §25).
///
/// # Este é o único lugar do aplicativo que entende códigos do Firebase
/// Acima daqui só circula [AppFailure]. Se um dia trocarmos de backend, é este
/// arquivo que muda — nem as telas, nem os controladores.
///
/// # Sobre as mensagens de autenticação
/// Elas são deliberadamente vagas quanto a *qual* parte falhou. Dizer
/// "este e-mail não existe" entrega ao atacante quais e-mails estão
/// cadastrados; "e-mail ou senha incorretos" não entrega nada e é igualmente
/// útil para quem está de boa-fé.
abstract final class FirebaseErrorMapper {
  /// Ponto de entrada único.
  static AppFailure map(Object error, [StackTrace? stackTrace]) {
    _log(error, stackTrace);

    return switch (error) {
      final AppFailure failure => failure,
      final FirebaseAuthException e => _auth(e),
      final FirebaseException e => _firebase(e),
      SocketException() => const AppFailure.network(),
      TimeoutException() => const AppFailure(
          kind: FailureKind.network,
          message: 'A operação demorou demais. Tente novamente.',
          code: 'timeout',
        ),
      _ => AppFailure.unknown(error.toString()),
    };
  }

  /// Envolve uma operação e garante que só [AppFailure] escape.
  ///
  /// O timeout é parte do contrato (§27): sem ele, uma rede instável deixa a
  /// tela girando para sempre em vez de dizer o que houve.
  static Future<T> guard<T>(
    Future<T> Function() operation, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    try {
      return await operation().timeout(timeout);
    } catch (error, stackTrace) {
      throw map(error, stackTrace);
    }
  }

  // -- Authentication ---------------------------------------------------------

  static AppFailure _auth(FirebaseAuthException e) {
    final String message = switch (e.code) {
      // Agrupados de propósito: a mensagem não revela se o e-mail existe.
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' ||
      'invalid-email' =>
        'E-mail ou senha incorretos.',
      'email-already-in-use' =>
        'Já existe uma conta com este e-mail. Tente entrar.',
      'weak-password' =>
        'Escolha uma senha mais forte, com pelo menos 8 caracteres.',
      'user-disabled' =>
        'Esta conta está desativada. Fale com o suporte.',
      'too-many-requests' =>
        'Muitas tentativas seguidas. Aguarde alguns minutos.',
      'requires-recent-login' =>
        'Por segurança, entre novamente antes de continuar.',
      'network-request-failed' =>
        'Sem conexão no momento. Verifique sua internet e tente de novo.',
      'operation-not-allowed' =>
        'Este método de acesso não está habilitado.',
      _ => 'Não foi possível concluir. Tente novamente.',
    };

    final FailureKind kind = switch (e.code) {
      'network-request-failed' => FailureKind.network,
      'too-many-requests' => FailureKind.quota,
      _ => FailureKind.authentication,
    };

    return AppFailure(
      kind: kind,
      message: message,
      code: e.code,
      technicalDetails: e.message,
    );
  }

  // -- Firestore, Storage e demais --------------------------------------------

  static AppFailure _firebase(FirebaseException e) {
    final String message = switch (e.code) {
      'permission-denied' || 'unauthorized' =>
        'Você não tem permissão para realizar esta ação.',
      'unavailable' || 'network-request-failed' || 'retry-limit-exceeded' =>
        'Sem conexão com o servidor. Tente novamente em instantes.',
      'deadline-exceeded' =>
        'A operação demorou demais. Tente novamente.',
      'not-found' || 'object-not-found' =>
        'Não encontramos o que você procura.',
      'already-exists' =>
        'Este registro já existe.',
      'resource-exhausted' || 'quota-exceeded' =>
        'Limite de uso atingido. Tente mais tarde.',
      'unauthenticated' =>
        'Sua sessão expirou. Entre novamente.',
      'cancelled' || 'canceled' =>
        'Operação cancelada.',
      'invalid-argument' || 'invalid-checksum' =>
        'Os dados enviados não são válidos.',
      _ => 'Algo não deu certo. Tente novamente em instantes.',
    };

    final FailureKind kind = switch (e.code) {
      'permission-denied' || 'unauthorized' => FailureKind.permission,
      'unavailable' ||
      'network-request-failed' ||
      'deadline-exceeded' ||
      'retry-limit-exceeded' =>
        FailureKind.network,
      'not-found' || 'object-not-found' => FailureKind.notFound,
      'resource-exhausted' || 'quota-exceeded' => FailureKind.quota,
      'unauthenticated' => FailureKind.authentication,
      'invalid-argument' || 'invalid-checksum' => FailureKind.validation,
      _ => FailureKind.unknown,
    };

    return AppFailure(
      kind: kind,
      message: message,
      code: e.code,
      technicalDetails: e.message,
    );
  }

  /// Registro do erro técnico (§35).
  ///
  /// Hoje escreve no console de depuração. Quando Crashlytics entrar, é aqui
  /// que ele é chamado — em um lugar só, e nunca com dado pessoal junto: o que
  /// se registra é o código do erro, não o conteúdo do documento.
  static void _log(Object error, StackTrace? stackTrace) {
    if (!kDebugMode) return;
    debugPrint('[Scorpions] falha de infraestrutura: $error');
    if (stackTrace != null) debugPrintStack(stackTrace: stackTrace);
  }
}
