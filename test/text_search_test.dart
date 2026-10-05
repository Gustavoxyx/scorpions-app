import 'package:flutter_test/flutter_test.dart';
import 'package:scorpions/core/utils/text_search.dart';
import 'package:scorpions/data/mock/mock_species.dart';
import 'package:scorpions/data/models/species.dart';
import 'package:scorpions/data/repositories/species_repository.dart';

/// Testes de `TextSearch` e `SearchIndex`.
///
/// # Por que este arquivo existe
/// A auditoria de otimização unificou duas cópias idênticas de uma função de
/// normalização (achado D-1) e trocou a busca linear por caractere por uma
/// tabela de consulta mais índice pré-calculado (achado P-1, 38 a 57 vezes mais
/// rápido, medido).
///
/// Otimização que muda o resultado não é otimização, é defeito. Então o que
/// estes testes guardam é o **comportamento**: a busca precisa achar
/// exatamente o que achava antes.
///
/// A implementação antiga está reproduzida aqui como oráculo. Ela é o padrão de
/// comparação — não porque estivesse certa por decreto, mas porque é o que o
/// aplicativo fazia, e mudar isso em silêncio seria mudar o produto sem dizer.
void main() {
  /// A implementação anterior, copiada sem alteração de
  /// `species_repository.dart` antes da unificação.
  String normalizeAntiga(String input) {
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

  group('TextSearch.normalize concorda com a implementação que substituiu', () {
    test('sobre o alfabeto acentuado inteiro e os casos de borda', () {
      const List<String> amostras = <String>[
        'Escorpião-amarelo',
        'Tityus serrulatus',
        'Bothriurus bonariensis',
        'áàâãäéèêëíìîïóòôõöúùûüçñ',
        'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ',
        '  espaços nas pontas  ',
        '',
        '   ',
        'São Paulo / Minas Gerais',
        'números 123 e símbolos @#%',
        'ÜBER-straße',
        'Opisthacanthus cayaporum',
      ];

      for (final String amostra in amostras) {
        expect(
          TextSearch.normalize(amostra),
          normalizeAntiga(amostra),
          reason: 'divergiu em: "$amostra"',
        );
      }
    });

    test('sobre todo o catálogo de demonstração', () {
      // Os dados reais, não só amostras escolhidas por mim. Se algum nome de
      // espécie tiver um caractere que eu não previ, é aqui que aparece.
      for (final Species s in MockSpecies.all) {
        expect(
          TextSearch.normalize(s.searchIndex),
          normalizeAntiga(s.searchIndex),
          reason: 'divergiu em ${s.scientificName}',
        );
      }
    });

    test('é idempotente — normalizar duas vezes não muda nada', () {
      // Importa porque `SearchIndex` normaliza o índice uma vez e a consulta
      // outra. Se não fosse idempotente, as duas passariam a divergir.
      for (final String amostra in <String>[
        'Escorpião',
        'ÁÉÍÓÚ',
        'já normalizado',
      ]) {
        final String uma = TextSearch.normalize(amostra);
        expect(TextSearch.normalize(uma), uma);
      }
    });
  });

  group('TextSearch.normalize faz o que promete', () {
    test('remove acento, baixa a caixa e corta espaço das pontas', () {
      expect(TextSearch.normalize('Escorpião'), 'escorpiao');
      expect(TextSearch.normalize('  AÇÃO  '), 'acao');
      expect(TextSearch.normalize('Ñandú'), 'nandu');
    });

    test('não mexe no que não é acentuado', () {
      expect(TextSearch.normalize('tityus 123 @#'), 'tityus 123 @#');
    });
  });

  group('SearchIndex', () {
    test('acha pelo nome sem acento o que está escrito com acento', () {
      // O propósito inteiro do mecanismo.
      final SearchIndex<String> indice = SearchIndex<String>(
        const <String>['Escorpião-amarelo', 'Escorpião-marrom', 'Lacrau'],
        (String s) => s,
      );

      expect(indice.search('escorpiao'), hasLength(2));
      expect(indice.search('amarelo'), <String>['Escorpião-amarelo']);
      expect(indice.search('LACRAU'), <String>['Lacrau']);
    });

    test('consulta vazia ou só espaço devolve tudo', () {
      final SearchIndex<String> indice = SearchIndex<String>(
        const <String>['a', 'b'],
        (String s) => s,
      );

      expect(indice.search(''), hasLength(2));
      expect(indice.search('   '), hasLength(2));
    });

    test('consulta sem correspondência devolve lista vazia, não tudo', () {
      // O erro oposto seria pior: devolver o catálogo inteiro quando nada
      // casa faria a tela parecer que a busca não funciona em vez de dizer
      // que não achou.
      final SearchIndex<String> indice = SearchIndex<String>(
        const <String>['Tityus'],
        (String s) => s,
      );

      expect(indice.search('zzzz'), isEmpty);
    });

    test('preserva a ordem da lista de origem', () {
      // A ordem vem do `orderBy('scientificName')` do Firestore. Se a busca
      // reordenasse, a lista do catálogo mudaria de ordem ao filtrar.
      final SearchIndex<String> indice = SearchIndex<String>(
        const <String>['Ananteris', 'Bothriurus', 'Opisthacanthus', 'Tityus'],
        (String s) => s,
      );

      expect(indice.search('s'), <String>[
        'Ananteris',
        'Bothriurus',
        'Opisthacanthus',
        'Tityus',
      ]);
    });

    test('lista vazia não quebra', () {
      final SearchIndex<String> indice =
          SearchIndex<String>(const <String>[], (String s) => s);

      expect(indice.search('qualquer'), isEmpty);
      expect(indice.search(''), isEmpty);
    });

    test('o resultado não é modificável', () {
      // Quem recebe o resultado da busca não deve conseguir alterar a lista
      // por dentro e afetar o que a próxima tela vê.
      final SearchIndex<String> indice =
          SearchIndex<String>(const <String>['a'], (String s) => s);

      expect(() => indice.search('a').add('b'), throwsUnsupportedError);
    });
  });

  group('MockSpeciesRepository.search continua respondendo o mesmo', () {
    const MockSpeciesRepository repositorio = MockSpeciesRepository();

    /// A busca como era antes da otimização, sobre os mesmos dados.
    List<Species> buscaAntiga(String query) {
      final String q = normalizeAntiga(query);
      if (q.isEmpty) return MockSpecies.all;
      return MockSpecies.all
          .where((Species s) => normalizeAntiga(s.searchIndex).contains(q))
          .toList();
    }

    test('para um conjunto amplo de consultas', () async {
      // Inclui consultas que acham muito, pouco e nada, com e sem acento, em
      // caixa alta e baixa.
      const List<String> consultas = <String>[
        '',
        '   ',
        'tityus',
        'Tityus',
        'TITYUS',
        'serrulatus',
        'escorpiao',
        'escorpião',
        'ESCORPIÃO',
        'amarelo',
        'buthidae',
        'bothriurus',
        'são paulo',
        'sao paulo',
        'minas',
        'zzzznaoexiste',
        't',
        'us',
      ];

      for (final String consulta in consultas) {
        final List<Species> agora = await repositorio.search(consulta);
        final List<Species> antes = buscaAntiga(consulta);

        expect(
          agora.map((Species s) => s.id).toList(),
          antes.map((Species s) => s.id).toList(),
          reason: 'a busca mudou de resultado para "$consulta"',
        );
      }
    });
  });
}
