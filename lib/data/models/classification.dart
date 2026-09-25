import 'package:flutter/foundation.dart';

/// Uma hipótese de espécie devolvida pelo classificador.
@immutable
class SpeciesCandidate {
  const SpeciesCandidate({
    required this.speciesId,
    required this.scientificName,
    required this.confidence,
  });

  final String speciesId;
  final String scientificName;

  /// Probabilidade de 0 a 1.
  final double confidence;

  Map<String, Object?> toMap() => <String, Object?>{
        'speciesId': speciesId,
        'scientificName': scientificName,
        'confidence': double.parse(confidence.toStringAsFixed(4)),
      };
}

/// Saída do classificador (briefing Fase 4, §13).
///
/// # Por que as alternativas vêm junto
/// Um classificador que devolve só o primeiro lugar esconde a informação mais
/// útil de todas: o quanto ele hesitou. Duas espécies com 0,46 e 0,44 são um
/// caso completamente diferente de uma com 0,92 — e a interface precisa poder
/// tratar os dois de formas diferentes, o que só é possível se o dado chegar.
@immutable
class ClassificationResult {
  const ClassificationResult({
    required this.candidates,
    required this.modelVersion,
    required this.isMock,
  });

  /// Nada foi classificado. Estado honesto enquanto não há modelo.
  const ClassificationResult.notEvaluated()
      : candidates = const <SpeciesCandidate>[],
        modelVersion = mockVersion,
        isMock = true;

  static const String mockVersion = 'mock-classifier-v1';

  /// Ordenadas da mais provável para a menos provável. Vazia quando não houve
  /// avaliação — o que não é o mesmo que "nenhuma espécie corresponde".
  final List<SpeciesCandidate> candidates;

  final String modelVersion;
  final bool isMock;

  bool get wasEvaluated => candidates.isNotEmpty;

  SpeciesCandidate? get top => candidates.isEmpty ? null : candidates.first;

  List<SpeciesCandidate> get alternatives =>
      candidates.isEmpty ? const <SpeciesCandidate>[] : candidates.skip(1).toList();

  Map<String, Object?> toMap() => <String, Object?>{
        'modelVersion': modelVersion,
        'isMock': isMock,
        'candidates':
            candidates.map((SpeciesCandidate c) => c.toMap()).toList(growable: false),
      };
}
