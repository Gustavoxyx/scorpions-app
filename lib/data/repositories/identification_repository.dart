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

  /// Registra o desfecho do envio das imagens num registro que já existe.
  ///
  /// # Por que não é um `save` com os campos preenchidos
  /// Porque `save` grava o documento inteiro, e `createdAt` é sempre um carimbo
  /// do servidor — reescrever tudo faria a data de criação pular para o
  /// momento do upload, bagunçando a ordem do histórico. Pior: a regra de
  /// segurança que mantém `createdAt` imutável recusaria a escrita.
  ///
  /// # Por que cobre também o fracasso
  /// Porque fracassar é um desfecho tão normal quanto o outro: hoje o Cloud
  /// Storage depende de um plano pago que o projeto ainda não tem, e o envio
  /// simplesmente não acontece. Quando isso ocorre, a identificação continua
  /// existindo — só que sem foto — e [errorCode] é o que permite à tela dizer
  /// isso ao usuário em vez de mostrar um registro mudo e quebrado.
  Future<void> attachUploadResult(
    String id, {
    String? imageUrl,
    String? thumbnailUrl,
    String? errorCode,
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
  Future<void> attachUploadResult(
    String id, {
    String? imageUrl,
    String? thumbnailUrl,
    String? errorCode,
  }) async {
    final int i = _items.indexWhere((IdentificationResult r) => r.id == id);
    if (i < 0) return;
    _items[i] = _items[i].copyWith(
      imageUrl: imageUrl,
      thumbnailUrl: thumbnailUrl,
      errorCode: errorCode,
    );
  }

  @override
  Future<void> delete(String id) async {
    _items.removeWhere((IdentificationResult i) => i.id == id);
  }
}
