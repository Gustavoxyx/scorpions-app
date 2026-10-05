import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/text_search.dart';
import '../models/species.dart';
import '../services/firebase_error_mapper.dart';
import 'species_repository.dart';

/// Catálogo científico vindo do Firestore (brief §29).
///
/// # Por que a busca é local
/// O Firestore não faz busca textual: `where` só compara valores inteiros, e
/// não existe "contém". As alternativas seriam prefixos com `>=`/`<` (que não
/// encontram "amarelo" dentro de "Escorpião-amarelo") ou um serviço externo de
/// indexação, que é peso demais para um catálogo desta ordem de grandeza.
///
/// Com dezenas — ou algumas centenas — de espécies, baixar a coleção uma vez e
/// filtrar em memória é mais rápido, mais barato e funciona offline. Quando o
/// catálogo crescer a ponto de isso doer, a troca é para Algolia ou Typesense
/// **atrás desta mesma interface**.
///
/// # Cache
/// A coleção é lida uma vez por sessão. O Firestore ainda mantém sua própria
/// persistência offline por baixo, então uma segunda abertura do app já mostra
/// o catálogo antes mesmo de a rede responder.
class FirestoreSpeciesRepository implements SpeciesRepository {
  FirestoreSpeciesRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Teto da listagem do catálogo.
  ///
  /// Baixar a coleção inteira é a decisão certa para esta ordem de grandeza
  /// (ver acima), mas "inteira" precisa ter fim. Sem o teto, um catálogo que
  /// crescesse por engano — um seed rodado duas vezes, uma importação com
  /// defeito — viraria download ilimitado em celular de banca, custo de
  /// leitura no Firestore e memória que o aparelho modesto não tem.
  ///
  /// 500 é folgado de propósito: a fauna de escorpiões descrita no Brasil não
  /// chega a 200 espécies, então o limite nunca é atingido em uso normal — ele
  /// existe para o caso anormal.
  static const int _maxCatalogo = 500;

  List<Species>? _cache;

  /// Índice de busca do catálogo em cache, montado junto dele.
  ///
  /// Normalizar o índice de cada espécie a cada tecla digitada custava
  /// 1.171 – 2.686 µs por tecla para 200 espécies; com o índice pronto, 31 – 47
  /// µs. Medido em `benchmark/search_normalization_benchmark.dart`.
  ///
  /// Nasce e morre com `_cache`: quem invalida um invalida o outro, senão a
  /// busca responderia sobre um catálogo que já foi descartado.
  SearchIndex<Species>? _indice;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('species');

  @override
  Future<List<Species>> fetchAll() async {
    final List<Species>? cached = _cache;
    if (cached != null) return cached;

    return FirebaseErrorMapper.guard(() async {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await _collection.orderBy('scientificName').limit(_maxCatalogo).get();

      final List<Species> species = snapshot.docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
              Species.fromMap(doc.id, doc.data()))
          .toList(growable: false);

      _cache = species;
      return species;
    });
  }

  @override
  Future<Species?> findById(String id) async {
    // Evita uma ida à rede quando a espécie já veio na listagem.
    final List<Species>? cached = _cache;
    if (cached != null) {
      for (final Species species in cached) {
        if (species.id == id) return species;
      }
    }

    return FirebaseErrorMapper.guard(() async {
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await _collection.doc(id).get();
      if (!doc.exists) return null;
      return Species.fromMap(doc.id, doc.data() ?? <String, dynamic>{});
    });
  }

  @override
  Future<List<Species>> search(String query) async {
    final List<Species> all = await fetchAll();
    // Monta na primeira busca, não em `fetchAll`: quem só abre a ficha de uma
    // espécie nunca paga por um índice que não vai consultar.
    final SearchIndex<Species> indice = _indice ??=
        SearchIndex<Species>(all, (Species s) => s.searchIndex);
    return indice.search(query);
  }

  /// Descarta o cache — usado pelo "puxar para atualizar".
  ///
  /// O índice vai junto, e não é detalhe: um índice sobrevivente apontaria para
  /// a lista antiga, devolvendo espécies que o catálogo recarregado já não tem.
  void invalidate() {
    _cache = null;
    _indice = null;
  }
}
