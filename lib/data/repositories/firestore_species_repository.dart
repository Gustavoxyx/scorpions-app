import 'package:cloud_firestore/cloud_firestore.dart';

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

  List<Species>? _cache;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('species');

  @override
  Future<List<Species>> fetchAll() async {
    final List<Species>? cached = _cache;
    if (cached != null) return cached;

    return FirebaseErrorMapper.guard(() async {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await _collection.orderBy('scientificName').get();

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
    final String normalized = _normalize(query);
    if (normalized.isEmpty) return all;

    return all
        .where((Species s) => _normalize(s.searchIndex).contains(normalized))
        .toList(growable: false);
  }

  /// Descarta o cache — usado pelo "puxar para atualizar".
  void invalidate() => _cache = null;

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
