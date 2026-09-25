import '../models/detection.dart';
import '../models/processed_image.dart';

/// Detecta se há um escorpião na imagem (briefing Fase 4, §12).
///
/// A interface existe agora para que a Fase 5 troque a implementação sem
/// reabrir o pipeline. Recebe a imagem já preparada — detectar na versão
/// processada, e não no original, é deliberado: é essa a imagem que o
/// classificador vai ver, então é nela que a caixa precisa fazer sentido.
abstract interface class ScorpionDetectionService {
  Future<ScorpionDetectionResult> detect(ProcessedImage image);
}

/// **SIMULADO.** Não detecta nada.
///
/// # Por que ele não inventa uma resposta
/// Seria fácil devolver `isScorpion: true` com confiança alta e deixar o
/// fluxo bonito. Seria também uma mentira embutida no produto: a tela
/// mostraria "escorpião detectado" sem que nada tenha sido detectado, e na
/// Fase 5 ninguém saberia distinguir o que o modelo acertou do que o
/// placeholder fabricou.
///
/// Este mock devolve **não avaliado**. O pipeline segue, a identificação é
/// gravada como `processing`, e a ausência de detecção fica registrada como
/// ausência — que é a verdade.
class MockScorpionDetectionService implements ScorpionDetectionService {
  const MockScorpionDetectionService();

  @override
  Future<ScorpionDetectionResult> detect(ProcessedImage image) async {
    return const ScorpionDetectionResult.unknown();
  }
}
