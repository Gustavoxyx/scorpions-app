/// Natureza de uma falha, para a interface decidir como reagir.
///
/// Não é o código do erro: é a **classe de problema**. A tela precisa saber se
/// vale oferecer "tentar novamente" (rede), se o pedido é inválido (validação)
/// ou se não há o que o usuário possa fazer (permissão).
enum FailureKind {
  /// Sem internet, timeout, servidor inalcançável. Recuperável tentando de novo.
  network,

  /// Credencial inválida, sessão expirada, e-mail já em uso.
  authentication,

  /// A operação não é permitida para este usuário. Repetir não resolve.
  permission,

  /// O dado enviado não passou na validação.
  validation,

  /// Recurso não encontrado.
  notFound,

  /// Cota, limite de taxa, abuso detectado.
  quota,

  /// Qualquer outra coisa.
  unknown,
}

/// Erro já traduzido para a linguagem do produto.
///
/// # Por que a UI nunca vê a exceção original (brief §25)
/// `FirebaseException: [cloud_firestore/permission-denied]` não ajuda ninguém
/// — e pior, expõe detalhe de infraestrutura. A tela recebe [message], em
/// português e acionável; [technicalDetails] fica disponível apenas para log.
///
/// Este tipo é o **único** que atravessa a fronteira do repositório para cima.
/// Nenhuma camada acima de `data/` importa `firebase_*`.
class AppFailure implements Exception {
  const AppFailure({
    required this.kind,
    required this.message,
    this.code,
    this.technicalDetails,
  });

  const AppFailure.network([String? message])
      : kind = FailureKind.network,
        message = message ??
            'Sem conexão no momento. Verifique sua internet e tente de novo.',
        code = null,
        technicalDetails = null;

  const AppFailure.permission([String? message])
      : kind = FailureKind.permission,
        message =
            message ?? 'Você não tem permissão para realizar esta ação.',
        code = null,
        technicalDetails = null;

  const AppFailure.unknown([String? details])
      : kind = FailureKind.unknown,
        message = 'Algo não deu certo. Tente novamente em instantes.',
        code = null,
        technicalDetails = details;

  final FailureKind kind;

  /// Texto exibido ao usuário. Sempre em português, sempre acionável.
  final String message;

  /// Código original (`permission-denied`, `unavailable`…). Para log e
  /// telemetria, nunca para a tela.
  final String? code;

  /// Detalhe técnico completo. Só vai para o log (§35).
  final String? technicalDetails;

  /// Se `true`, faz sentido a tela oferecer "tentar novamente".
  bool get isRetryable =>
      kind == FailureKind.network || kind == FailureKind.unknown;

  @override
  String toString() =>
      'AppFailure(${kind.name}${code == null ? '' : ', $code'}): $message';
}
