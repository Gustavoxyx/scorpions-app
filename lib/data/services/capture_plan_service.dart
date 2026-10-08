import '../models/capture_instruction.dart';
import '../models/image_quality.dart';

/// Decide qual será a segunda fotografia.
///
/// # Por que é um serviço e não um `if` na tela
/// O briefing (§2, §3) pede que a escolha possa depender da primeira imagem,
/// da qualidade dela e, mais adiante, das espécies candidatas. Nada disso é
/// assunto de widget. Com a decisão atrás de uma interface, a Fase 5 troca a
/// implementação sem tocar na tela de captura, e um teste consegue exercitar
/// a regra sem montar interface nenhuma.
abstract interface class CapturePlanService {
  /// A primeira instrução. Igual para todos, sempre.
  ImageCaptureInstruction primary();

  /// A segunda, escolhida a partir do que a primeira produziu.
  ///
  /// [primaryQuality] é nulo quando a primeira imagem é simulada — modo de
  /// demonstração, desktop, teste. Nesse caso a escolha cai no padrão.
  ImageCaptureInstruction secondary({ImageQualityResult? primaryQuality});
}

/// Estratégia em vigor enquanto não há modelo.
///
/// # O que ela faz hoje, e por que isso não é adivinhação
/// Sem classificador, não há espécie candidata, e sem espécie candidata não há
/// como saber qual região separa *esta* dúvida. Então a escolha não tenta
/// adivinhar a espécie: ela reage ao **que foi medido na primeira foto**, que
/// é informação real e disponível agora.
///
/// A regra tem uma única inversão, e ela é deliberada:
///
/// - Primeira foto **nítida e bem exposta** → pede a **cauda**. É a vista com
///   maior poder de separação entre as espécies do catálogo publicado, em
///   que três de cinco são *Tityus*: a serrilha dos últimos segmentos é o
///   caráter clássico de identificação do gênero.
///
/// - Primeira foto **no limite da nitidez** → pede **o perfil**, não um close.
///   Um aparelho que não conseguiu focar o animal inteiro vai falhar pior
///   numa aproximação, onde a profundidade de campo é menor. Insistir no close
///   produziria uma segunda foto pior que a primeira, e duas imagens ruins não
///   somam — o §5 diz exatamente isso.
///
/// Quando houver modelo, esta classe é substituída por uma que consulta as
/// candidatas. A interface não muda.
class HeuristicCapturePlanService implements CapturePlanService {
  const HeuristicCapturePlanService();

  @override
  ImageCaptureInstruction primary() => ImageCaptureInstruction.primary;

  @override
  ImageCaptureInstruction secondary({ImageQualityResult? primaryQuality}) {
    if (primaryQuality == null) return ImageCaptureInstruction.tail;

    final bool focoFragil = primaryQuality.warnings.any(
      (ImageQualityWarning w) =>
          w == ImageQualityWarning.blurry || w == ImageQualityWarning.softFocus,
    );
    if (focoFragil) return ImageCaptureInstruction.sideView;

    // Resolução baixa tem o mesmo efeito prático que desfoque num close: não
    // há pixels suficientes na região para o detalhe aparecer.
    final bool poucosPixels = primaryQuality.warnings.contains(
      ImageQualityWarning.lowResolution,
    );
    if (poucosPixels) return ImageCaptureInstruction.sideView;

    return ImageCaptureInstruction.tail;
  }
}
