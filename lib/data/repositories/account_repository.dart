import 'package:flutter/foundation.dart';

import '../../core/constants/app_environment.dart';
import '../services/backend_client.dart';
import '../services/failure.dart';

/// Quanto da cota diária foi usado.
@immutable
class QuotaSnapshot {
  const QuotaSnapshot({
    required this.used,
    required this.limit,
  });

  final int used;
  final int limit;

  int get remaining => (limit - used).clamp(0, limit);
  bool get exhausted => used >= limit;

  /// Avisar antes de acabar, não quando acabou.
  ///
  /// Descobrir o limite depois de enquadrar o animal, focar e disparar é
  /// descobrir tarde — a foto já foi tirada e não serve para nada.
  bool get isLow => remaining > 0 && remaining <= 5;

  static QuotaSnapshot fromMap(Map<String, Object?> map) => QuotaSnapshot(
        used: (map['used'] as num?)?.toInt() ?? 0,
        limit: (map['limit'] as num?)?.toInt() ?? 0,
      );
}

/// O recibo da exclusão de conta.
@immutable
class DeletionReceipt {
  const DeletionReceipt({
    required this.images,
    required this.identifications,
    this.requestId,
  });

  final int images;
  final int identifications;
  final String? requestId;

  static DeletionReceipt fromMap(Map<String, Object?> map) => DeletionReceipt(
        images: (map['images'] as num?)?.toInt() ?? 0,
        identifications: (map['identifications'] as num?)?.toInt() ?? 0,
        requestId: map['requestId'] as String?,
      );
}

/// Levantada quando o servidor pede a senha de novo.
///
/// Um tipo próprio, e não um [AppFailure] genérico, porque a tela precisa
/// **reagir** a isto de um jeito específico: abrir o pedido de senha, não
/// mostrar um erro. Um `AppFailure` seria tratado como falha, e falha é o que
/// isto não é — é um passo do fluxo.
class ReauthenticationRequired implements Exception {
  const ReauthenticationRequired();
}

/// Operações sobre a própria conta (LGPD, Art. 18).
///
/// # Por que isto passa pelo backend
/// A exclusão em cascata precisa de privilégio que o cliente não tem: as
/// Security Rules negam `delete` em `users/{uid}` justamente para que ninguém
/// apague o perfil e deixe as imagens órfãs. Quem tem o privilégio é o Admin
/// SDK, que vive só no servidor.
///
/// Fechou o HIGH-2 da auditoria: antes disto, **não havia caminho nenhum** para
/// o titular apagar os próprios dados.
abstract interface class AccountRepository {
  /// Exclusão definitiva, em cascata.
  ///
  /// Levanta [ReauthenticationRequired] se o login não for recente. A tela pede
  /// a senha, reautentica e chama de novo.
  Future<DeletionReceipt> deleteAccount();

  /// Todos os dados do titular, para portabilidade (Art. 18, V).
  Future<Map<String, Object?>> exportData();

  /// Consumo da cota de hoje. `null` quando não foi possível saber.
  Future<QuotaSnapshot?> quota();
}

class BackendAccountRepository implements AccountRepository {
  const BackendAccountRepository(this._client);

  final BackendClient _client;

  @override
  Future<DeletionReceipt> deleteAccount() async {
    final BackendResponse r = await _client.delete('/v1/me');

    if (r.isSuccess) return DeletionReceipt.fromMap(r.body);

    // Reautenticação vem antes dos outros casos de 401: os dois usam o mesmo
    // código, e a diferença está no cabeçalho. Tratar na ordem inversa faria
    // "digite a senha" virar "sua sessão expirou", e o usuário sairia da conta
    // sem precisar.
    if (r.needsReauth) throw const ReauthenticationRequired();

    throw _traduzir(r, acao: 'excluir a conta');
  }

  @override
  Future<Map<String, Object?>> exportData() async {
    final BackendResponse r = await _client.get('/v1/me/data');
    if (r.isSuccess) return r.body;
    throw _traduzir(r, acao: 'exportar seus dados');
  }

  @override
  Future<QuotaSnapshot?> quota() async {
    try {
      final BackendResponse r = await _client.get('/v1/me/quota');
      if (!r.isSuccess) return null;
      return QuotaSnapshot.fromMap(r.body);
    } on AppFailure {
      // Saber a cota é conveniência. Uma tela que não abre porque não
      // conseguiu ler um contador é pior que uma tela sem o contador.
      return null;
    }
  }

  /// Converte a resposta do servidor em erro de produto.
  ///
  /// A mensagem do servidor é preferida quando existe: ela é mais específica e
  /// já foi escrita para ser lida por uma pessoa — o backend é responsável por
  /// não vazar detalhe interno ali (§17). O texto genérico é o último recurso.
  AppFailure _traduzir(BackendResponse r, {required String acao}) {
    final String? doServidor = r.detail;

    return switch (r.statusCode) {
      401 => AppFailure(
          kind: FailureKind.authentication,
          message: doServidor ?? 'Sua sessão expirou. Entre novamente.',
          code: 'unauthenticated',
          technicalDetails: r.requestId,
        ),
      403 => AppFailure(
          kind: FailureKind.permission,
          message: doServidor ?? 'Você não tem permissão para $acao.',
          code: 'forbidden',
          technicalDetails: r.requestId,
        ),
      429 => AppFailure(
          kind: FailureKind.quota,
          message: doServidor ?? 'Muitas tentativas. Tente de novo mais tarde.',
          code: 'rate_limited',
          technicalDetails: r.requestId,
        ),
      503 => AppFailure(
          kind: FailureKind.network,
          message: doServidor ??
              'O serviço está indisponível agora. Tente mais tarde.',
          code: 'unavailable',
          technicalDetails: r.requestId,
        ),
      _ => AppFailure(
          kind: FailureKind.unknown,
          message: doServidor ?? 'Não foi possível $acao. Tente novamente.',
          code: 'http_${r.statusCode}',
          technicalDetails: r.requestId,
        ),
    };
  }
}

/// Implementação para quando não há backend configurado.
///
/// # Por que existe em vez de deixar nulo
/// Sem ela, cada tela precisaria verificar se o repositório existe antes de
/// usá-lo, e uma delas esqueceria. Com ela, a chamada acontece e falha com uma
/// frase que **diz o motivo** — que é o comportamento certo para o modo de
/// demonstração, para os testes de widget e para um build sem `BACKEND_URL`.
///
/// O que ela nunca faz é **fingir que apagou**. Devolver um recibo falso de
/// exclusão seria a pior coisa possível aqui: o usuário acreditaria que os
/// dados dele foram embora.
class UnavailableAccountRepository implements AccountRepository {
  const UnavailableAccountRepository();

  AppFailure get _indisponivel => AppFailure(
        kind: FailureKind.network,
        message: AppEnvironmentConfig.backendUnavailableReason ??
            'Este recurso precisa do serviço online.',
        code: 'backend_not_configured',
      );

  @override
  Future<DeletionReceipt> deleteAccount() async => throw _indisponivel;

  @override
  Future<Map<String, Object?>> exportData() async => throw _indisponivel;

  @override
  Future<QuotaSnapshot?> quota() async => null;
}
