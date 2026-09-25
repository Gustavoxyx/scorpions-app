import '../models/classification.dart';
import '../models/processed_image.dart';

/// Classifica a espécie a partir da imagem (briefing Fase 4, §13).
///
/// Vazia de propósito nesta fase. A Fase 5 traz `TfliteSpeciesClassifier` ou
/// `RemoteSpeciesClassifier` implementando este mesmo contrato, e nada acima
/// precisa mudar.
abstract interface class SpeciesClassificationService {
  Future<ClassificationResult> classify(ProcessedImage image);
}

/// **SIMULADO.** Não classifica nada.
///
/// Devolve lista vazia, e não uma espécie sorteada. O `MockIdentificationService`
/// da Fase 1 sorteia espécies de propósito — ele existe para exercitar a
/// interface em modo de demonstração, e tudo que ele produz carrega o selo de
/// dado simulado. Este aqui é outra coisa: é o lugar do modelo real no
/// pipeline, e preenchê-lo com sorteio faria o registro gravado no banco
/// parecer uma classificação que nunca aconteceu.
class MockSpeciesClassificationService implements SpeciesClassificationService {
  const MockSpeciesClassificationService();

  @override
  Future<ClassificationResult> classify(ProcessedImage image) async {
    return const ClassificationResult.notEvaluated();
  }
}
