/// Busca textual tolerante a acentos.
///
/// # Por que existe num lugar só
/// A função de normalização existia **duplicada palavra por palavra** em
/// `species_repository.dart` e `firestore_species_repository.dart`, com o mesmo
/// comentário nos dois. Mesma responsabilidade, mesma saída — a auditoria de
/// otimização (D-1) a trouxe para cá.
///
/// Note que `view_prediction.dart` também tem um `_normalize`, e ele **não**
/// veio: aquele normaliza uma distribuição de probabilidade para somar 1. Nome
/// igual, responsabilidade sem relação. Juntar os dois produziria uma função
/// que faz duas coisas incompatíveis.
///
/// # Por que uma tabela em vez de `indexOf`
/// A versão anterior procurava cada caractere numa string de 26 posições com
/// `indexOf` — busca linear, por caractere, a cada tecla digitada. Medido em
/// `benchmark/search_normalization_benchmark.dart`, sobre 200 espécies:
///
/// | estratégia | custo por tecla |
/// |---|---|
/// | `indexOf` numa string | 1.171 – 2.686 µs |
/// | tabela de consulta | 675 – 1.265 µs |
/// | índice pré-normalizado (ver [SearchIndex]) | **31 – 47 µs** |
///
/// O benchmark verifica que a saída é idêntica à da versão anterior, sobre o
/// alfabeto acentuado inteiro, antes de comparar tempos — senão estaria
/// cronometrando coisas diferentes.
abstract final class TextSearch {
  /// Vogais e consoantes acentuadas mapeadas para a forma sem acento, por
  /// ponto de código.
  ///
  /// Consulta em tempo constante, no lugar de varrer uma string. Só minúsculas:
  /// a entrada passa por `toLowerCase()` antes.
  static const Map<int, int> _semAcento = <int, int>{
    0xE1: 0x61, 0xE0: 0x61, 0xE2: 0x61, 0xE3: 0x61, 0xE4: 0x61, // á à â ã ä
    0xE9: 0x65, 0xE8: 0x65, 0xEA: 0x65, 0xEB: 0x65, //             é è ê ë
    0xED: 0x69, 0xEC: 0x69, 0xEE: 0x69, 0xEF: 0x69, //             í ì î ï
    0xF3: 0x6F, 0xF2: 0x6F, 0xF4: 0x6F, 0xF5: 0x6F, 0xF6: 0x6F, // ó ò ô õ ö
    0xFA: 0x75, 0xF9: 0x75, 0xFB: 0x75, 0xFC: 0x75, //             ú ù û ü
    0xE7: 0x63, //                                                 ç
    0xF1: 0x6E, //                                                 ñ
  };

  /// Minúsculas, sem acento, sem espaço nas pontas — para que "escorpiao"
  /// encontre "escorpião".
  static String normalize(String input) {
    final StringBuffer buffer = StringBuffer();
    for (final int rune in input.toLowerCase().runes) {
      buffer.writeCharCode(_semAcento[rune] ?? rune);
    }
    return buffer.toString().trim();
  }
}

/// Índice de busca já normalizado, calculado uma vez por lista.
///
/// # O problema que resolve
/// `search()` normalizava o índice de **cada** espécie a **cada** tecla
/// digitada. Nada era reaproveitado entre teclas, e o índice de busca de
/// `Species` é um getter calculado — então cada comparação montava uma lista
/// nova, fazia `join`, `toLowerCase` e então percorria caractere por caractere.
///
/// # Honestidade sobre o ganho
/// 1,2 ms por tecla **não é visível**: o orçamento de um quadro a 60 FPS é
/// 16,7 ms. Isto não corrige um travamento que exista hoje. O que justifica é
/// o que vem: em aparelho de entrada o fator costuma ser 5 a 10 vezes pior, e
/// o catálogo é previsto crescer bem além de 200 espécies. Nessas duas
/// condições juntas, a busca passa a comer o quadro.
class SearchIndex<T> {
  /// Monta o índice. O custo — medido em 649 – 1.475 µs para 200 itens — é
  /// pago **uma vez**, não por tecla.
  SearchIndex(List<T> items, String Function(T) keyOf)
      : _items = items,
        _keys = List<String>.generate(
          items.length,
          (int i) => TextSearch.normalize(keyOf(items[i])),
          growable: false,
        );

  final List<T> _items;
  final List<String> _keys;

  /// Itens cujo índice contém [query]. Consulta vazia devolve tudo.
  List<T> search(String query) {
    final String q = TextSearch.normalize(query);
    if (q.isEmpty) return _items;

    final List<T> achados = <T>[];
    for (int i = 0; i < _keys.length; i++) {
      if (_keys[i].contains(q)) achados.add(_items[i]);
    }
    return List<T>.unmodifiable(achados);
  }
}
