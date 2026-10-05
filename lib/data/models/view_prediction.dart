import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'capture_instruction.dart';
import 'classification.dart';

/// O que o classificador respondeu para **uma** das vistas.
///
/// Guardar por vista, e não só o resultado final, é o que torna possível
/// responder depois "a segunda foto mudou alguma coisa?" — a pergunta do §27.
/// Se só guardássemos a fusão, a contribuição de cada imagem seria
/// irrecuperável.
@immutable
class ViewPrediction {
  const ViewPrediction({
    required this.captureType,
    required this.candidates,
    required this.modelVersion,
    this.qualityWeight = 1.0,
  });

  final CaptureType captureType;

  /// Ordenados do mais provável para o menos provável.
  final List<SpeciesCandidate> candidates;

  final String modelVersion;

  /// Quanto esta vista deve pesar, de 0 a 1, por causa da qualidade da imagem.
  final double qualityWeight;

  bool get isEmpty => candidates.isEmpty;

  SpeciesCandidate? get top => candidates.isEmpty ? null : candidates.first;

  /// Distância entre o primeiro e o segundo lugar.
  ///
  /// É a medida de hesitação do modelo **nesta vista**. Um 0,92 contra 0,04 e
  /// um 0,48 contra 0,44 podem ter o mesmo campeão e significam coisas
  /// completamente diferentes. Vale 1 quando só há um candidato.
  double get margin {
    if (candidates.isEmpty) return 0;
    if (candidates.length == 1) return 1;
    return candidates[0].confidence - candidates[1].confidence;
  }

  /// A distribuição como mapa espécie → score, para as operações de conjunto.
  Map<String, double> get distribution => <String, double>{
        for (final SpeciesCandidate c in candidates) c.speciesId: c.confidence,
      };

  Map<String, Object?> toMap() => <String, Object?>{
        'captureType': captureType.id,
        'modelVersion': modelVersion,
        'qualityWeight': double.parse(qualityWeight.toStringAsFixed(3)),
        'margin': double.parse(margin.toStringAsFixed(4)),
        'candidates':
            candidates.map((SpeciesCandidate c) => c.toMap()).toList(growable: false),
      };
}

/// O quanto as vistas concordam entre si (§13).
///
/// # Por que três medidas e não uma
/// Porque elas respondem a perguntas diferentes, e usar só uma esconde casos
/// que importam:
///
/// - **Concordar no primeiro lugar** é binário e grosseiro. Duas vistas podem
///   apontar a mesma espécie com 0,91 e com 0,34 — mesma resposta, graus de
///   convicção incomparáveis.
/// - **Sobreposição no Top-3** pega o caso em que as vistas discordam de quem
///   vence mas consideram o mesmo pequeno conjunto. Isso é desacordo brando,
///   muito diferente de olharem para lados opostos do catálogo.
/// - **Divergência de distribuição** é a medida contínua, e é a que a
///   Confidence Engine usa. As outras duas existem para explicar o número a um
///   humano — o especialista que receber o caso precisa entender o conflito,
///   não só vê-lo quantificado.
@immutable
class CrossViewConsistency {
  const CrossViewConsistency({
    required this.agreeOnTop1,
    required this.topKOverlap,
    required this.distributionAgreement,
  });

  /// Única vista: não há com o que comparar.
  ///
  /// Marcado como acordo total de propósito. A alternativa — tratar como
  /// conflito — penalizaria quem só conseguiu uma foto, que é precisamente a
  /// situação em que o usuário mais precisa de uma resposta.
  const CrossViewConsistency.singleView()
      : agreeOnTop1 = true,
        topKOverlap = 1.0,
        distributionAgreement = 1.0;

  /// As vistas elegeram a mesma espécie.
  final bool agreeOnTop1;

  /// Fração do Top-3 que as vistas têm em comum, de 0 a 1.
  final double topKOverlap;

  /// Acordo entre as distribuições completas, de 0 a 1.
  ///
  /// Calculado como `1 - JS`, onde JS é a divergência de Jensen-Shannon em
  /// base 2. Vale 1 para distribuições idênticas e 0 para distribuições sem
  /// nenhuma massa em comum.
  final double distributionAgreement;

  /// Desacordo em que as vistas apontam espécies diferentes **e** mal
  /// consideram as mesmas hipóteses. É o caso que o §14 manda não resolver
  /// por conta própria.
  bool get isConflicting => !agreeOnTop1 && topKOverlap < 0.5;

  Map<String, Object?> toMap() => <String, Object?>{
        'agreeOnTop1': agreeOnTop1,
        'topKOverlap': double.parse(topKOverlap.toStringAsFixed(3)),
        'distributionAgreement':
            double.parse(distributionAgreement.toStringAsFixed(4)),
      };

  // ---------------------------------------------------------------------------
  // Cálculo
  // ---------------------------------------------------------------------------

  /// Mede a concordância entre duas predições.
  static CrossViewConsistency between(ViewPrediction a, ViewPrediction b, {int k = 3}) {
    if (a.isEmpty || b.isEmpty) return const CrossViewConsistency.singleView();

    final Set<String> topA =
        a.candidates.take(k).map((SpeciesCandidate c) => c.speciesId).toSet();
    final Set<String> topB =
        b.candidates.take(k).map((SpeciesCandidate c) => c.speciesId).toSet();

    // Jaccard: o quanto os dois conjuntos se sobrepõem em relação ao total
    // considerado. Preferido à interseção crua porque não depende de as duas
    // listas terem o mesmo tamanho.
    final int uniao = topA.union(topB).length;
    final double overlap =
        uniao == 0 ? 1.0 : topA.intersection(topB).length / uniao;

    return CrossViewConsistency(
      agreeOnTop1: a.top!.speciesId == b.top!.speciesId,
      topKOverlap: overlap,
      distributionAgreement:
          1.0 - _jensenShannon(a.distribution, b.distribution),
    );
  }

  /// Divergência de Jensen-Shannon em base 2, no intervalo [0, 1].
  ///
  /// # Por que esta e não outra
  /// A escolha óbvia seria Kullback-Leibler, mas KL é assimétrica — `KL(A‖B)`
  /// difere de `KL(B‖A)` — e aqui nenhuma das duas vistas é a referência da
  /// outra; são pares. KL também explode para infinito quando uma distribuição
  /// dá massa zero a algo que a outra considera, e isso acontece o tempo todo:
  /// o modelo devolve Top-3, então quase toda espécie tem zero em alguma das
  /// listas.
  ///
  /// Jensen-Shannon resolve as duas coisas. É simétrica por construção e,
  /// como compara cada lado com a média dos dois, nunca divide por zero. Em
  /// base 2 fica limitada a 1, o que dá uma escala interpretável sem
  /// normalização arbitrária.
  static double _jensenShannon(Map<String, double> p, Map<String, double> q) {
    final Set<String> chaves = <String>{...p.keys, ...q.keys};
    if (chaves.isEmpty) return 0;

    final Map<String, double> pn = _normalize(p, chaves);
    final Map<String, double> qn = _normalize(q, chaves);

    double divergencia = 0;
    for (final String chave in chaves) {
      final double pi = pn[chave]!;
      final double qi = qn[chave]!;
      final double mi = (pi + qi) / 2;
      if (mi <= 0) continue;
      if (pi > 0) divergencia += 0.5 * pi * (math.log(pi / mi) / math.ln2);
      if (qi > 0) divergencia += 0.5 * qi * (math.log(qi / mi) / math.ln2);
    }

    // Erro de ponto flutuante pode produzir -1e-17 ou 1.0000000002.
    return divergencia.clamp(0.0, 1.0);
  }

  /// Completa com zeros as espécies ausentes e reescala para somar 1.
  ///
  /// A reescala é necessária porque o modelo devolve apenas o Top-N: a soma
  /// dos scores entregues é menor que 1, e comparar duas distribuições de
  /// massas diferentes mediria a diferença de corte, não a de opinião.
  static Map<String, double> _normalize(
    Map<String, double> origem,
    Set<String> chaves,
  ) {
    double soma = 0;
    for (final String chave in chaves) {
      soma += origem[chave] ?? 0;
    }
    if (soma <= 0) {
      final double uniforme = 1 / chaves.length;
      return <String, double>{for (final String c in chaves) c: uniforme};
    }
    return <String, double>{
      for (final String c in chaves) c: (origem[c] ?? 0) / soma,
    };
  }
}
