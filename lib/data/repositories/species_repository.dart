import '../../core/utils/text_search.dart';
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

  /// Índice montado uma vez para o processo inteiro.
  ///
  /// `MockSpecies.all` é uma lista estática e imutável, então o índice dela
  /// também pode ser.
  ///
  /// Sem `late`, e isso não é descuido: em Dart, **toda** variável estática é
  /// inicializada de forma preguiçosa, na primeira leitura. O custo já cai na
  /// primeira busca e não na carga da classe — que é o que importa aqui, porque
  /// abrir o aplicativo não deve pagar por uma tela que o usuário talvez não
  /// visite. O `late` que estava escrito aqui não acrescentava nada, e o
  /// analisador apontou.
  static final SearchIndex<Species> _indice =
      SearchIndex<Species>(MockSpecies.all, (Species s) => s.searchIndex);

  @override
  Future<List<Species>> fetchAll() async => MockSpecies.all;

  @override
  Future<Species?> findById(String id) async => MockSpecies.byId(id);

  @override
  Future<List<Species>> search(String query) async => _indice.search(query);
}
