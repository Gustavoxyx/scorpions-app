import 'package:flutter_test/flutter_test.dart';
import 'package:scorpions/data/models/species.dart';

/// Mede o custo da busca no catálogo.
///
/// # Por que este arquivo existe
/// A auditoria de otimização encontrou que `search()` chama `_normalize` sobre
/// o `searchIndex` de **cada** espécie a **cada** tecla digitada, e que
/// `_normalize` percorre caractere por caractere fazendo `indexOf` numa string
/// de 26 posições.
///
/// O §41 do briefing proíbe estimar: *"Não inventar métricas."* Então antes de
/// propor a mudança, o custo é medido aqui.
///
/// Este arquivo não faz parte do aplicativo. Ele mede, e por isso vive fora de
/// `test/` — não deve rodar no CI junto da verificação de correção, onde um
/// número de tempo variaria com a carga da máquina e quebraria o verde sem
/// haver defeito.
///
///     flutter test benchmark/search_normalization_benchmark.dart
void main() {
  // -- Candidato A: a implementação de hoje, copiada sem alteração ------------

  String normalizeAtual(String input) {
    const String from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const String to = 'aaaaaeeeeiiiiooooouuuucn';
    final StringBuffer buffer = StringBuffer();
    for (final int rune in input.toLowerCase().runes) {
      final String char = String.fromCharCode(rune);
      final int index = from.indexOf(char);
      buffer.write(index >= 0 ? to[index] : char);
    }
    return buffer.toString().trim();
  }

  // -- Candidato B: mesma saída, tabela de consulta em vez de busca linear ----

  const Map<int, int> tabela = <int, int>{
    0xE1: 0x61, 0xE0: 0x61, 0xE2: 0x61, 0xE3: 0x61, 0xE4: 0x61, // á à â ã ä
    0xE9: 0x65, 0xE8: 0x65, 0xEA: 0x65, 0xEB: 0x65, //             é è ê ë
    0xED: 0x69, 0xEC: 0x69, 0xEE: 0x69, 0xEF: 0x69, //             í ì î ï
    0xF3: 0x6F, 0xF2: 0x6F, 0xF4: 0x6F, 0xF5: 0x6F, 0xF6: 0x6F, // ó ò ô õ ö
    0xFA: 0x75, 0xF9: 0x75, 0xFB: 0x75, 0xFC: 0x75, //             ú ù û ü
    0xE7: 0x63, 0xF1: 0x6E, //                                     ç ñ
  };

  String normalizeTabela(String input) {
    final StringBuffer buffer = StringBuffer();
    for (final int rune in input.toLowerCase().runes) {
      buffer.writeCharCode(tabela[rune] ?? rune);
    }
    return buffer.toString().trim();
  }

  // -- Catálogo sintético ----------------------------------------------------
  //
  // 200 espécies é a ordem de grandeza real: a fauna de escorpiões descrita no
  // Brasil não chega a 200 espécies (ver `ImageLimits` e
  // `FirestoreSpeciesRepository._maxCatalogo`). O `searchIndex` tem o
  // comprimento típico — nome científico, nome popular, família, regiões.

  List<Species> catalogo(int quantas) {
    return List<Species>.generate(
      quantas,
      (int i) => Species(
        id: 'especie-$i',
        scientificName: 'Tityus serrulatus variação $i',
        commonName: 'Escorpião-amarelo-do-cerrado nº $i',
        family: 'Buthidae',
        genus: 'Tityus',
        specificEpithet: 'serrulatus',
        summary: 'resumo irrelevante para a busca',
        sizeRange: '6 a 7 cm',
        coloration: 'amarelo-claro',
        behaviour: 'noturno',
        distribution: const <String>['São Paulo', 'Minas Gerais', 'Goiás'],
        habitats: const <String>['ambientes peridomiciliares'],
        medicalRelevance: MedicalRelevance.significant,
        medicalNotes: 'nota irrelevante para a busca',
        morphology: const <MorphologyFeature>[],
        accentSeed: i,
      ),
      growable: false,
    );
  }

  /// Executa [acao] repetidas vezes e devolve o melhor tempo por repetição.
  ///
  /// O **melhor**, não a média: a média mede também o escalonador do sistema,
  /// a coleta de lixo e o que mais estiver rodando nesta máquina. O menor
  /// tempo observado é o mais próximo do custo real do código.
  Duration medir(String rotulo, int repeticoes, void Function() acao) {
    // Aquece: as primeiras execuções pagam compilação JIT e primeira alocação.
    for (int i = 0; i < 3; i++) {
      acao();
    }

    Duration melhor = const Duration(days: 1);
    for (int i = 0; i < repeticoes; i++) {
      final Stopwatch cronometro = Stopwatch()..start();
      acao();
      cronometro.stop();
      if (cronometro.elapsed < melhor) melhor = cronometro.elapsed;
    }

    // ignore: avoid_print
    print('  $rotulo: ${melhor.inMicroseconds} µs');
    return melhor;
  }

  test('custo de uma busca no catálogo, por estratégia', () {
    final List<Species> especies = catalogo(200);
    const String consulta = 'amarelo';

    // ignore: avoid_print
    print('\n--- busca em catálogo de ${especies.length} espécies ---');

    // A: como está hoje. Normaliza o índice de cada espécie a cada tecla.
    final Duration a = medir('A  hoje (normaliza tudo a cada tecla)', 200, () {
      final String q = normalizeAtual(consulta);
      especies
          .where((Species s) => normalizeAtual(s.searchIndex).contains(q))
          .toList(growable: false);
    });

    // B: mesma estrutura, só troca indexOf por tabela de consulta.
    final Duration b = medir('B  tabela de consulta', 200, () {
      final String q = normalizeTabela(consulta);
      especies
          .where((Species s) => normalizeTabela(s.searchIndex).contains(q))
          .toList(growable: false);
    });

    // C: índice pré-normalizado uma vez, na montagem do catálogo.
    final List<String> indicePronto = especies
        .map((Species s) => normalizeTabela(s.searchIndex))
        .toList(growable: false);

    final Duration c = medir('C  índice pré-normalizado', 200, () {
      final String q = normalizeTabela(consulta);
      final List<Species> achadas = <Species>[];
      for (int i = 0; i < especies.length; i++) {
        if (indicePronto[i].contains(q)) achadas.add(especies[i]);
      }
    });

    // Custo pago uma vez, na primeira busca, para montar o índice de C.
    medir('   (montagem do índice de C, custo único)', 50, () {
      especies.map((Species s) => normalizeTabela(s.searchIndex)).toList();
    });

    // ignore: avoid_print
    print(
      '\n  B é ${(a.inMicroseconds / b.inMicroseconds).toStringAsFixed(1)}x '
      'mais rápido que A'
      '\n  C é ${(a.inMicroseconds / c.inMicroseconds).toStringAsFixed(1)}x '
      'mais rápido que A\n',
    );

    // As três precisam concordar no resultado, senão a comparação não vale.
    final String q = normalizeAtual(consulta);
    final int porA = especies
        .where((Species s) => normalizeAtual(s.searchIndex).contains(q))
        .length;
    final int porB = especies
        .where((Species s) => normalizeTabela(s.searchIndex).contains(q))
        .length;
    final int porC = indicePronto.where((String i) => i.contains(q)).length;

    expect(porB, porA, reason: 'a tabela mudou o resultado da busca');
    expect(porC, porA, reason: 'o índice pronto mudou o resultado da busca');
    expect(porA, greaterThan(0), reason: 'a consulta precisa achar algo');
  });

  test('as duas normalizações produzem exatamente a mesma saída', () {
    // Sem isto o benchmark compararia coisas diferentes. Cobre o alfabeto
    // acentuado inteiro mais os casos de borda.
    const List<String> amostras = <String>[
      'Escorpião-amarelo',
      'Tityus serrulatus',
      'áàâãäéèêëíìîïóòôõöúùûüçñ',
      'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ',
      '  espaços nas pontas  ',
      '',
      'ÜBER-straße',
      'São Paulo / Minas Gerais',
      'números 123 e símbolos @#%',
    ];

    for (final String amostra in amostras) {
      expect(
        normalizeTabela(amostra),
        normalizeAtual(amostra),
        reason: 'divergiram em: "$amostra"',
      );
    }
  });
}
