/// Limiares da decisão de identificação (§12, §15).
///
/// # Por que todos aqui
/// O briefing proíbe limiares espalhados pelo código e, em particular, dentro
/// da interface. A razão é prática: calibrar um sistema significa mexer nesses
/// números repetidamente, e um número que mora dentro de um `if` numa tela é
/// um número que ninguém encontra quando precisa mudar — e que silenciosamente
/// diverge do seu gêmeo em outra tela.
///
/// # AVISO QUE PRECISA SER LIDO ANTES DE USAR ESTES NÚMEROS
///
/// **Nenhum destes valores foi calibrado.** Eles não vêm de um conjunto de
/// validação, porque ainda não existe modelo nem dataset. São pontos de
/// partida escolhidos por raciocínio sobre a estrutura do problema, e estão
/// aqui para que o sistema tenha um comportamento definido — não porque
/// alguém mediu que funcionam.
///
/// O briefing é explícito em não afirmar precisão que não foi medida (§16,
/// §28). Enquanto [calibrated] for `false`, a interface não deve apresentar
/// nenhum destes números ao usuário como probabilidade, e o relatório de
/// métricas deve dizer que a decisão opera com limiares provisórios.
///
/// Quando o modelo existir, estes valores saem de um conjunto de validação:
/// escolhe-se o ponto que equilibra erro de identificação contra taxa de
/// encaminhamento humano, e o diagrama de confiabilidade mostra se o score
/// pode ou não ser lido como probabilidade.
abstract final class DecisionThresholds {
  /// Vira `true` quando os limiares passarem por um conjunto de validação.
  ///
  /// Enquanto for `false`, o sistema funciona, mas nada que dependa destes
  /// números pode ser apresentado como medida.
  static const bool calibrated = false;

  // -- Score da hipótese vencedora --------------------------------------------

  /// Abaixo disto, nenhuma hipótese é considerada aceitável e o resultado é
  /// rejeição — o `UNKNOWN_SPECIES` do §17.
  ///
  /// Com cinco espécies no catálogo, o acaso dá 0,20. Um vencedor abaixo de
  /// 0,35 está perto demais do chute para virar afirmação sobre um animal
  /// peçonhento.
  static const double rejectBelow = 0.35;

  /// Piso para resultado automático.
  static const double highScore = 0.75;

  /// Piso para resultado com ressalva.
  static const double mediumScore = 0.50;

  // -- Margem entre o primeiro e o segundo lugar ------------------------------

  /// Distância mínima para que o primeiro lugar seja tratado como escolha, e
  /// não como empate.
  ///
  /// Esta medida importa mais que o score absoluto. Um vencedor com 0,80
  /// contra um segundo de 0,78 não é uma identificação: é um empate com
  /// aparência de vitória, e apresentá-lo como resposta seria o erro mais
  /// caro que este sistema pode cometer.
  static const double decisiveMargin = 0.20;

  /// Abaixo disto o modelo não escolheu — hesitou. Vai para revisão humana.
  static const double ambiguousMargin = 0.08;

  // -- Acordo entre as vistas (§13) -------------------------------------------

  /// Acordo mínimo entre as distribuições para resultado automático.
  static const double consistentViews = 0.70;

  /// Abaixo disto, as vistas discordam a ponto de a fusão não ser confiável.
  /// O §14 manda não resolver isso por conta própria.
  static const double conflictingViews = 0.40;

  // -- Qualidade ---------------------------------------------------------------

  /// Quanto uma imagem ruim reduz o peso dela na fusão.
  ///
  /// Não é zero de propósito: uma foto ruim ainda carrega informação, e
  /// descartá-la por completo desperdiçaria o esforço que o usuário já fez.
  static const double poorQualityWeight = 0.35;
  static const double acceptableQualityWeight = 0.75;
  static const double goodQualityWeight = 1.0;
}
