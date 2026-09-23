import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/firestore_codec.dart';

/// Converte os mapas produzidos pelos modelos em mapas que o Firestore aceita.
///
/// # O que ele resolve
/// Os modelos são Dart puro e não conseguem produzir um
/// `FieldValue.serverTimestamp()` sem importar o SDK. Eles emitem
/// [FirestoreCodec.serverTimestamp] e este arquivo faz a substituição — é a
/// única peça que precisa conhecer os dois lados.
///
/// # Por que o carimbo é do servidor
/// O relógio do aparelho pode estar errado (fuso trocado, data manual, bateria
/// esgotada). A ordenação do histórico e qualquer auditoria futura dependem de
/// um tempo confiável, e o único confiável é o do servidor.
abstract final class FirestoreWriteMapper {
  /// Aplica a substituição recursivamente, inclusive dentro de listas e mapas
  /// aninhados.
  static Map<String, Object?> prepare(Map<String, Object?> data) {
    return data.map(
      (String key, Object? value) => MapEntry<String, Object?>(
        key,
        _convert(value),
      ),
    );
  }

  static Object? _convert(Object? value) {
    if (FirestoreCodec.isServerTimestamp(value)) {
      return FieldValue.serverTimestamp();
    }
    if (value is Map<String, Object?>) return prepare(value);
    if (value is List) return value.map(_convert).toList(growable: false);
    return value;
  }
}
