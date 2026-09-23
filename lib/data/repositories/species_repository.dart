import '../mock/mock_species.dart';
import '../models/species.dart';

/// Acesso ao catálogo científico.
///
/// Fase 1: [MockSpeciesRepository] lê a lista estática de `data/mock`.
/// Fase 7: `FirestoreSpeciesRepository` lê a coleção `species`, com cache
/// offline. A assinatura assíncrona já está pronta para isso.
abstract interface class SpeciesRepository {
  Future<List<Species>> fetchAll();

  Future<Species?> findById(String id);

  /// Busca textual por nome científico, nome popular, família ou região.
  Future<List<Species>> search(String query);
}

class MockSpeciesRepository implements SpeciesRepository {
  const MockSpeciesRepository();

  @override
  Future<List<Species>> fetchAll() async => MockSpecies.all;

  @override
  Future<Species?> findById(String id) async => MockSpecies.byId(id);

  @override
  Future<List<Species>> search(String query) async {
    final String q = _normalize(query);
    if (q.isEmpty) return MockSpecies.all;
    return MockSpecies.all
        .where((Species s) => _normalize(s.searchIndex).contains(q))
        .toList();
  }

  /// Remove acentos para que "escorpiao" encontre "escorpião".
  static String _normalize(String input) {
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
}
