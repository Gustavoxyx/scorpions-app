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

  /// Liga as imagens já enviadas a um registro que existe.
  ///
  /// # Por que não é um `save` com os campos preenchidos
  /// Porque `save` grava o documento inteiro, e `createdAt` é sempre um carimbo
  /// do servidor — reescrever tudo faria a data de criação pular para o
  /// momento do upload, bagunçando a ordem do histórico. Pior: a regra de
  /// segurança que mantém `createdAt` imutável recusaria a escrita.
  ///
  /// Esta operação toca apenas os dois campos que o envio produz.
  Future<void> attachImages(
    String id, {
    String? imageUrl,
    String? thumbnailUrl,
  });

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
  Future<void> attachImages(
    String id, {
    String? imageUrl,
    String? thumbnailUrl,
  }) async {
    final int i = _items.indexWhere((IdentificationResult r) => r.id == id);
    if (i < 0) return;
    _items[i] = _items[i].copyWith(
      imageUrl: imageUrl,
      thumbnailUrl: thumbnailUrl,
    );
  }

  @override
  Future<void> delete(String id) async {
    _items.removeWhere((IdentificationResult i) => i.id == id);
  }
}
