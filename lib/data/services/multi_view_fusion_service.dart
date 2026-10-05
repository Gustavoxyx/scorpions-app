import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/classification.dart';
import '../models/view_prediction.dart';

/// Como as evidências das duas vistas são combinadas (§9).
///
/// # O que não está aqui, e por quê
/// O briefing lista quatro famílias: late fusion, early fusion, feature fusion
/// e modelo multi-view treinado. Só a primeira é implementável deste lado.
///
/// As outras três acontecem **dentro** do modelo: early fusion empilha os
/// canais das duas imagens na entrada, feature fusion concatena os embeddings
/// antes do classificador, e o modelo multi-view é treinado desde o início
/// para receber duas vistas. Nenhuma delas é uma operação sobre scores — todas
/// exigem o modelo construído de outro jeito.
///
/// Implementá-las aqui seria encenação. O que este arquivo faz é o que dá para
/// fazer com o que o classificador devolve, e o que vai servir de linha de
/// base contra a qual as outras serão medidas quando existirem.
enum FusionStrategy {
  /// Média aritmética dos scores por espécie.
  ///
  /// A linha de base. Trata as vistas como igualmente informativas, o que é
  /// falso — a vista de cima carrega mais informação que um close borrado —
  /// mas é a referência honesta contra a qual as outras precisam provar ganho.
  average('average'),

  /// Maior score por espécie entre as vistas.
  ///
  /// Parte da ideia de que uma vista pode simplesmente **ver** o caráter que a
  /// outra não mostra. O preço é não punir o desacordo: se uma vista diz 0,9
  /// para A e a outra diz 0,9 para B, as duas saem com 0,9 e a fusão fica sem
  /// opinião. Por isso a consistência cruzada é medida à parte e entra na
  /// decisão — não dentro da fusão.
  maximum('maximum'),

  /// Média ponderada pela convicção de cada vista.
  ///
  /// O peso é a margem Top1–Top2 daquela vista. Uma vista que hesitou entre
  /// duas espécies contribui menos que uma que foi direta. É o que mais se
  /// aproxima de "ouvir quem tem mais a dizer".
  confidenceWeighted('confidence_weighted'),

  /// Média ponderada pela qualidade da imagem.
  ///
  /// O peso vem de fora do modelo — brilho, contraste e nitidez medidos pelo
  /// pipeline. Útil exatamente quando o modelo **não** sabe que está olhando
  /// para uma foto ruim, que é o caso em que ele erra com confiança.
  qualityWeighted('quality_weighted');

  const FusionStrategy(this.id);

  final String id;
}

/// O resultado da combinação.
@immutable
class FusedPrediction {
  const FusedPrediction({
    required this.candidates,
    required this.rawTopScore,
    required this.strategy,
    required this.consistency,
    required this.viewCount,
    required this.modelVersions,
  });

  /// Nada a fundir — nenhuma vista produziu predição.
  const FusedPrediction.notEvaluated()
      : candidates = const <SpeciesCandidate>[],
        rawTopScore = 0,
        strategy = FusionStrategy.average,
        consistency = const CrossViewConsistency.singleView(),
        viewCount = 0,
        modelVersions = const <String>[];

  /// Pontuação do vencedor **antes** da renormalização.
  ///
  /// # Por que este campo existe
  /// Porque renormalizar apaga a informação mais importante que o modelo tem a
  /// dar: a de que ele não está convencido de nada.
  ///
  /// Um caso medido: duas vistas devolvendo `{x: 0,30, y: 0,28}` e
  /// `{y: 0,31, x: 0,29}`. A média dá 0,295 para cada — probabilidade
  /// espalhada, nenhuma hipótese sustentada, exatamente o `UNKNOWN_SPECIES`
  /// do §17. Mas a soma dos candidatos listados é 0,59, e reescalar para 1
  /// transforma os 0,295 em **0,50**. O mesmo modelo indeciso passa a
  /// aparentar meia certeza, e o limiar de rejeição nunca dispara.
  ///
  /// Então as duas coisas são separadas: [candidates] vem renormalizado,
  /// porque é o que a tela mostra e precisa somar 1; [rawTopScore] fica cru,
  /// porque é o que a decisão de rejeitar precisa olhar.
  ///
  /// Um teste pegou isto antes de existir qualquer modelo.
  final double rawTopScore;

  final List<SpeciesCandidate> candidates;
  final FusionStrategy strategy;
  final CrossViewConsistency consistency;
  final int viewCount;

  /// Versões dos modelos que produziram as evidências. Plural porque o §14
  /// prevê classificadores diferentes por vista.
  final List<String> modelVersions;

  bool get wasEvaluated => candidates.isNotEmpty;

  SpeciesCandidate? get top => candidates.isEmpty ? null : candidates.first;

  /// Top-3 (§11).
  List<SpeciesCandidate> get topThree =>
      candidates.take(3).toList(growable: false);

  /// Hesitação da fusão: distância entre o primeiro e o segundo lugar.
  double get margin {
    if (candidates.isEmpty) return 0;
    if (candidates.length == 1) return 1;
    return candidates[0].confidence - candidates[1].confidence;
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'strategy': strategy.id,
        'viewCount': viewCount,
        'modelVersions': modelVersions,
        'margin': double.parse(margin.toStringAsFixed(4)),
        'rawTopScore': double.parse(rawTopScore.toStringAsFixed(4)),
        'consistency': consistency.toMap(),
        'candidates': topThree
            .map((SpeciesCandidate c) => c.toMap())
            .toList(growable: false),
      };
}

/// Combina as evidências das vistas numa predição só.
abstract interface class MultiViewFusionService {
  FusedPrediction fuse(
    List<ViewPrediction> predictions, {
    FusionStrategy strategy,
  });
}

/// Implementação por combinação tardia de scores.
///
/// Sem estado e determinística de propósito: a mesma entrada produz sempre a
/// mesma saída, o que é condição para o §39 (reconstruir uma identificação) e
/// para comparar estratégias num experimento.
class LateFusionService implements MultiViewFusionService {
  const LateFusionService();

  @override
  FusedPrediction fuse(
    List<ViewPrediction> predictions, {
    FusionStrategy strategy = FusionStrategy.confidenceWeighted,
  }) {
    final List<ViewPrediction> usaveis = predictions
        .where((ViewPrediction p) => !p.isEmpty)
        .toList(growable: false);

    if (usaveis.isEmpty) return const FusedPrediction.notEvaluated();

    final CrossViewConsistency acordo = usaveis.length < 2
        ? const CrossViewConsistency.singleView()
        : CrossViewConsistency.between(usaveis[0], usaveis[1]);

    // União do que foi citado. Uma espécie ausente de uma vista conta como
    // zero ali, e não como "não considerada" — do contrário, o que aparece em
    // apenas uma das listas teria a média calculada sobre um divisor menor e
    // sairia artificialmente na frente.
    final Set<String> ids = <String>{
      for (final ViewPrediction p in usaveis)
        for (final SpeciesCandidate c in p.candidates) c.speciesId,
    };

    final Map<String, String> nomes = <String, String>{
      for (final ViewPrediction p in usaveis)
        for (final SpeciesCandidate c in p.candidates)
          c.speciesId: c.scientificName,
    };

    final List<double> pesos = _pesos(usaveis, strategy);

    final Map<String, double> combinado = <String, double>{};
    for (final String id in ids) {
      combinado[id] = switch (strategy) {
        FusionStrategy.maximum => _maiorScore(usaveis, id),
        _ => _mediaPonderada(usaveis, id, pesos),
      };
    }

    final List<SpeciesCandidate> ordenados = combinado.entries
        .map((MapEntry<String, double> e) => SpeciesCandidate(
              speciesId: e.key,
              scientificName: nomes[e.key] ?? e.key,
              confidence: e.value,
            ))
        .toList()
      // Desempate por identificador, e não é detalhe: com dois scores iguais,
      // a ordem passaria a depender da ordem de iteração de um `Set`. Isso
      // tornaria a saída dependente da ordem em que as espécies apareceram
      // nas listas de entrada — uma variável escondida, e uma fonte de
      // divergência com a implementação do servidor, que precisa produzir
      // exatamente o mesmo resultado.
      ..sort((SpeciesCandidate a, SpeciesCandidate b) {
        final int porScore = b.confidence.compareTo(a.confidence);
        return porScore != 0 ? porScore : a.speciesId.compareTo(b.speciesId);
      });

    return FusedPrediction(
      // Guardado antes da reescala. Ver a justificativa em `rawTopScore`.
      rawTopScore: ordenados.isEmpty ? 0 : ordenados.first.confidence,
      candidates: _renormalizar(ordenados),
      strategy: strategy,
      consistency: acordo,
      viewCount: usaveis.length,
      modelVersions: usaveis
          .map((ViewPrediction p) => p.modelVersion)
          .toSet()
          .toList(growable: false),
    );
  }

  // -- Interno ----------------------------------------------------------------

  static List<double> _pesos(List<ViewPrediction> vistas, FusionStrategy modo) {
    final List<double> brutos = switch (modo) {
      // A margem mede convicção, mas uma vista que hesitou não deve ser
      // silenciada por completo — ela ainda viu alguma coisa. O piso de 0,1
      // mantém a contribuição pequena em vez de nula.
      FusionStrategy.confidenceWeighted =>
        vistas.map((ViewPrediction p) => math.max(p.margin, 0.1)).toList(),
      FusionStrategy.qualityWeighted =>
        vistas.map((ViewPrediction p) => math.max(p.qualityWeight, 0.1)).toList(),
      _ => List<double>.filled(vistas.length, 1.0),
    };

    final double soma = brutos.fold(0.0, (double a, double b) => a + b);
    if (soma <= 0) return List<double>.filled(vistas.length, 1 / vistas.length);
    return brutos.map((double p) => p / soma).toList(growable: false);
  }

  static double _mediaPonderada(
    List<ViewPrediction> vistas,
    String speciesId,
    List<double> pesos,
  ) {
    double soma = 0;
    for (int i = 0; i < vistas.length; i++) {
      soma += (vistas[i].distribution[speciesId] ?? 0) * pesos[i];
    }
    return soma;
  }

  static double _maiorScore(List<ViewPrediction> vistas, String speciesId) {
    double maior = 0;
    for (final ViewPrediction v in vistas) {
      final double s = v.distribution[speciesId] ?? 0;
      if (s > maior) maior = s;
    }
    return maior;
  }

  /// Reescala para somar 1.
  ///
  /// Necessário porque as entradas já vêm truncadas no Top-N, e a estratégia
  /// `maximum` nem sequer preserva a soma. Sem isto, o número apresentado ao
  /// usuário dependeria de quantas hipóteses o modelo resolveu listar.
  ///
  /// **Isto não é calibração.** Reescalar faz os valores somarem 1; não os
  /// torna probabilidades. A §16 e a §28 tratam disso, e a interface nunca
  /// deve dizer "90% de chance de estar certo" a partir daqui.
  static List<SpeciesCandidate> _renormalizar(List<SpeciesCandidate> lista) {
    final double soma =
        lista.fold(0.0, (double a, SpeciesCandidate c) => a + c.confidence);
    if (soma <= 0) return lista;
    return lista
        .map((SpeciesCandidate c) => SpeciesCandidate(
              speciesId: c.speciesId,
              scientificName: c.scientificName,
              confidence: c.confidence / soma,
            ))
        .toList(growable: false);
  }
}
