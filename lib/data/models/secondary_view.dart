import 'package:flutter/foundation.dart';

import 'capture_instruction.dart';
import 'captured_image.dart';
import 'firestore_codec.dart';

/// A segunda fotografia de uma identificação, como fica registrada.
///
/// # Por que um mapa aninhado, e não uma lista de vistas
/// Os campos de topo do documento (`imageUrl`, `thumbnailUrl`, `imageQuality`)
/// já descrevem a primeira foto, e o histórico inteiro foi construído sobre
/// eles. Transformar tudo numa lista `views` obrigaria a migrar cada registro
/// existente e a reescrever a listagem — para ganhar uma generalidade que o
/// produto não pede: o briefing fixa **duas** fotos, e o backend recusa a
/// terceira.
///
/// Então a segunda vista entra como um acréscimo. Um registro de uma foto só
/// continua sendo exatamente o que era.
///
/// # O que o cliente escreve aqui, e o que não escreve
/// Só o que ele produziu: qual vista foi pedida, onde a imagem foi parar e o
/// que o aparelho mediu dela. **Nenhuma conclusão.** O que a segunda foto
/// "disse" sobre a espécie é resultado de análise, e resultado de análise nasce
/// no servidor (auditoria HIGH-1) — ver [MultiViewSummary].
@immutable
class SecondaryView {
  const SecondaryView({
    required this.captureType,
    required this.instructionId,
    required this.image,
    this.imageUrl,
    this.thumbnailUrl,
    this.imageQuality,
  });

  /// O que foi **pedido**. Guardado junto do que foi obtido para que, mais
  /// tarde, dê para perguntar "o usuário fotografou a cauda quando pedimos a
  /// cauda?" — pergunta impossível se só a imagem fosse guardada.
  final CaptureType captureType;
  final String instructionId;

  /// Imagem local. Num registro vindo do banco é uma referência remota.
  final CapturedImage image;

  final String? imageUrl;
  final String? thumbnailUrl;

  /// Medidas de qualidade, como gravadas. Mapa opaco pelo mesmo motivo de
  /// `IdentificationResult.imageQuality`: aqui é registro, não regra.
  final Map<String, Object?>? imageQuality;

  SecondaryView copyWith({String? imageUrl, String? thumbnailUrl}) {
    return SecondaryView(
      captureType: captureType,
      instructionId: instructionId,
      image: image,
      imageUrl: imageUrl ?? this.imageUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      imageQuality: imageQuality,
    );
  }

  /// As chaves são exatamente as que a Security Rules aceita em
  /// `secondaryView`. Acrescentar uma aqui sem acrescentar lá faz a criação do
  /// documento ser recusada — e o teste de contrato pega isso antes do usuário.
  Map<String, Object?> toMap() => <String, Object?>{
        'captureType': captureType.id,
        'instructionId': instructionId,
        'imageUrl': imageUrl,
        'thumbnailUrl': thumbnailUrl,
        'imageQuality': imageQuality,
      };

  /// `null` quando o documento não tem segunda vista — que é o caso de todo
  /// registro anterior a este campo.
  static SecondaryView? fromMap(Object? raw, {required DateTime capturedAt}) {
    final Map<String, dynamic> map = FirestoreCodec.map(raw);
    if (map.isEmpty) return null;

    final String? imageUrl = FirestoreCodec.stringOrNull(map['imageUrl']);
    final Map<String, dynamic> qualidade =
        FirestoreCodec.map(map['imageQuality']);

    return SecondaryView(
      captureType: CaptureType.fromId(FirestoreCodec.string(map['captureType'])),
      instructionId: FirestoreCodec.string(map['instructionId']),
      image: CapturedImage.remote(url: imageUrl, capturedAt: capturedAt),
      imageUrl: imageUrl,
      thumbnailUrl: FirestoreCodec.stringOrNull(map['thumbnailUrl']),
      imageQuality:
          qualidade.isEmpty ? null : Map<String, Object?>.from(qualidade),
    );
  }
}

/// O que a análise concluiu sobre o **conjunto** das vistas.
///
/// # Campo de servidor
/// Gravado sob a chave `fusion`, que está em `serverOwnedFields()` nas Security
/// Rules: o cliente não consegue escrevê-la. Se pudesse, forjaria "as duas
/// fotos concordaram" do mesmo jeito que forjaria `confidence: 0.99`.
///
/// No modo de demonstração ela é preenchida pelo aplicativo — sobre predições
/// simuladas, com o selo de dado simulado na tela, e sem tocar em banco nenhum.
/// A aritmética é a de produção; a entrada é que não é.
@immutable
class MultiViewSummary {
  const MultiViewSummary({
    required this.viewCount,
    required this.agreeOnTop1,
    required this.agreement,
    required this.decisionLevel,
    required this.reasons,
    required this.thresholdsCalibrated,
  });

  final int viewCount;

  /// As duas vistas apontaram a mesma espécie como mais provável.
  final bool agreeOnTop1;

  /// Concordância entre as distribuições, de 0 a 1 (1 − Jensen-Shannon).
  final double agreement;

  /// Identificador de `DecisionLevel`, como gravado.
  final String decisionLevel;

  /// Identificadores de `DecisionReason`, como gravados.
  final List<String> reasons;

  /// Se os limiares que produziram [decisionLevel] foram calibrados com dados.
  ///
  /// Hoje é sempre `false`, e a tela **diz isso**. Mostrar "alta confiança"
  /// sem avisar que o corte de "alta" ainda é um palpite seria afirmar uma
  /// precisão que ninguém mediu.
  final bool thresholdsCalibrated;

  bool get usedBothViews => viewCount >= 2;

  Map<String, Object?> toMap() => <String, Object?>{
        'viewCount': viewCount,
        'agreeOnTop1': agreeOnTop1,
        'agreement': double.parse(agreement.toStringAsFixed(4)),
        'decisionLevel': decisionLevel,
        'reasons': reasons,
        'thresholdsCalibrated': thresholdsCalibrated,
      };

  static MultiViewSummary? fromMap(Object? raw) {
    final Map<String, dynamic> map = FirestoreCodec.map(raw);
    if (map.isEmpty) return null;

    final Object? razoes = map['reasons'];
    return MultiViewSummary(
      viewCount: FirestoreCodec.number(map['viewCount']).round(),
      agreeOnTop1: FirestoreCodec.boolean(map['agreeOnTop1'], fallback: false),
      agreement: FirestoreCodec.number(map['agreement']),
      decisionLevel: FirestoreCodec.string(map['decisionLevel']),
      reasons: razoes is List<Object?>
          ? razoes.whereType<String>().toList(growable: false)
          : const <String>[],
      // Falhar para "não calibrado": um documento sem o campo não pode ser
      // lido como se alguém tivesse validado os limiares.
      thresholdsCalibrated: FirestoreCodec.boolean(
        map['thresholdsCalibrated'],
        fallback: false,
      ),
    );
  }
}
