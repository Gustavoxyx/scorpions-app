import '../mock/mock_history.dart';
import '../models/identification.dart';

/// Persistência das identificações do usuário.
///
/// Fase 1: [InMemoryIdentificationRepository], semeado com histórico fictício.
/// Fase 3: `FirestoreIdentificationRepository` — documento por identificação,
/// imagem no Cloud Storage, escrita autorizada por regras de segurança e
/// jamais direto do cliente sem validação.
abstract interface class IdentificationRepository {
  Future<List<IdentificationResult>> fetchHistory();

  Future<IdentificationResult?> findById(String id);

  Future<void> save(IdentificationResult result);

  Future<void> delete(String id);
}

class InMemoryIdentificationRepository implements IdentificationRepository {
  InMemoryIdentificationRepository({bool seedWithMockData = true})
      : _items = seedWithMockData
            ? MockHistory.seed()
            : <IdentificationResult>[];

  final List<IdentificationResult> _items;

  @override
  Future<List<IdentificationResult>> fetchHistory() async {
    final List<IdentificationResult> sorted =
        List<IdentificationResult>.of(_items)
          ..sort((IdentificationResult a, IdentificationResult b) =>
              b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  @override
  Future<IdentificationResult?> findById(String id) async {
    for (final IdentificationResult item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Future<void> save(IdentificationResult result) async {
    _items.removeWhere((IdentificationResult i) => i.id == result.id);
    _items.add(result);
  }

  @override
  Future<void> delete(String id) async {
    _items.removeWhere((IdentificationResult i) => i.id == id);
  }
}
