/// Conversões entre documentos do banco e os modelos do domínio.
///
/// # Por que os modelos não importam `cloud_firestore`
/// Um `Species` ou um `AppUser` são conceitos do produto, não do Firebase.
/// Mantê-los em Dart puro traz três benefícios concretos:
///
/// 1. Testes de modelo rodam sem inicializar Firebase nenhum.
/// 2. Trocar o backend (ou acrescentar um cache local em SQLite) não obriga a
///    reescrever os modelos.
/// 3. A camada de repositório vira o único lugar que conhece o SDK — que é
///    exatamente a fronteira que o brief §23 pede.
///
/// O preço é este arquivo: um punhado de conversores defensivos. Vale a pena.
///
/// # Por que todo leitor é tolerante
/// Um documento pode ter sido gravado por uma versão anterior do aplicativo,
/// ter um campo nulo, ou ter um tipo inesperado. Nenhuma dessas situações pode
/// derrubar uma tela. Todo leitor aqui tem um valor de queda.
abstract final class FirestoreCodec {
  /// Marcador de "carimbo do servidor".
  ///
  /// Os modelos não podem produzir um `FieldValue.serverTimestamp()` sem
  /// importar o SDK, então emitem esta sentinela e o repositório a substitui
  /// na hora de gravar (ver `FirestoreWriteMapper`).
  ///
  /// Usar o relógio do servidor — e não o do aparelho — importa: o relógio do
  /// celular pode estar errado, e a ordenação do histórico depende disso.
  static const Object serverTimestamp = _ServerTimestampSentinel();

  static bool isServerTimestamp(Object? value) =>
      value is _ServerTimestampSentinel;

  // -- Leitores ---------------------------------------------------------------

  static String string(Object? raw, {String fallback = ''}) =>
      raw is String ? raw : fallback;

  static String? stringOrNull(Object? raw) =>
      raw is String && raw.isNotEmpty ? raw : null;

  static int integer(Object? raw, {int fallback = 0}) => switch (raw) {
        final int value => value,
        final double value => value.round(),
        final String value => int.tryParse(value) ?? fallback,
        _ => fallback,
      };

  static double number(Object? raw, {double fallback = 0}) => switch (raw) {
        final double value => value,
        final int value => value.toDouble(),
        final String value => double.tryParse(value) ?? fallback,
        _ => fallback,
      };

  static bool boolean(Object? raw, {bool fallback = false}) =>
      raw is bool ? raw : fallback;

  /// Aceita `Timestamp` do Firestore, `DateTime`, milissegundos ou ISO-8601.
  ///
  /// O `Timestamp` é reconhecido por comportamento (`toDate()`), não por tipo:
  /// é o que permite este arquivo continuar sem importar o SDK.
  static DateTime? dateTime(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is String) return DateTime.tryParse(raw);
    try {
      final Object? converted = (raw as dynamic).toDate();
      if (converted is DateTime) return converted;
    } catch (_) {
      // Não é um Timestamp; cai para nulo abaixo.
    }
    return null;
  }

  /// Data com queda para "agora" — para campos que a UI precisa exibir sempre.
  ///
  /// Acontece legitimamente logo após uma escrita: o `serverTimestamp` só é
  /// resolvido quando o servidor confirma, e a leitura otimista local devolve
  /// nulo nesse intervalo.
  static DateTime dateTimeOrNow(Object? raw) => dateTime(raw) ?? DateTime.now();

  static List<String> stringList(Object? raw) {
    if (raw is! List) return const <String>[];
    return raw.whereType<String>().toList(growable: false);
  }

  static List<Map<String, dynamic>> mapList(Object? raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
  }

  static Map<String, dynamic> map(Object? raw) {
    if (raw is Map<Object?, Object?>) return Map<String, dynamic>.from(raw);
    return const <String, dynamic>{};
  }
}

/// Tipo privado da sentinela. Privado para que ninguém consiga construir outra
/// instância e confundir a substituição feita no repositório.
class _ServerTimestampSentinel {
  const _ServerTimestampSentinel();
}
