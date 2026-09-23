import 'package:flutter/foundation.dart';

import '../data/models/species.dart';
import '../data/repositories/species_repository.dart';
import '../data/services/failure.dart';

/// Estado da aba Catálogo.
///
/// Busca textual e filtro por família são combinados: o repositório resolve o
/// texto (é ele que falará com o Firestore na Fase 7) e o filtro taxonômico é
/// aplicado sobre o resultado. Manter os dois separados evita transformar o
/// filtro em mais um parâmetro de consulta remota antes de ser necessário.
class CatalogController extends ChangeNotifier {
  CatalogController(this._repository) {
    load();
  }

  final SpeciesRepository _repository;

  /// Resultado bruto da busca textual, antes do filtro de família.
  List<Species> _matches = <Species>[];

  List<Species> _results = <Species>[];
  List<Species> get results => _results;

  String _query = '';
  String get query => _query;

  /// Famílias presentes no catálogo, em ordem alfabética.
  List<String> _families = <String>[];
  List<String> get families => _families;

  /// Família selecionada. `null` significa "todas".
  String? _family;
  String? get family => _family;

  bool _loading = true;
  bool get loading => _loading;

  bool get isEmpty => !_loading && _results.isEmpty;

  /// Verdadeiro quando há busca ou filtro ativo. A tela usa isto para escolher
  /// entre "nenhum resultado para este filtro" e "catálogo vazio".
  bool get isFiltered => _query.isNotEmpty || _family != null;

  /// Mensagem já traduzida, quando a carga falha (§25).
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool get hasError => _errorMessage != null;

  Future<void> load() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final List<Species> all = await _repository.fetchAll();
      _families = all
          .map((Species s) => s.family)
          .where((String family) => family.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      _matches = all;
      _applyFilter();
    } on AppFailure catch (failure) {
      _errorMessage = failure.message;
    } catch (_) {
      _errorMessage = 'Não foi possível carregar o catálogo.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> search(String query) async {
    _query = query;
    _loading = true;
    notifyListeners();

    try {
      _matches = await _repository.search(query);
      _applyFilter();
      _errorMessage = null;
    } on AppFailure catch (failure) {
      _errorMessage = failure.message;
    } catch (_) {
      _errorMessage = 'Não foi possível buscar no catálogo.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Alterna a família selecionada. Tocar na família já ativa limpa o filtro.
  void toggleFamily(String family) {
    _family = _family == family ? null : family;
    _applyFilter();
    notifyListeners();
  }

  void clearFilters() {
    _query = '';
    _family = null;
    load();
  }

  void clearSearch() => search('');

  void _applyFilter() {
    _results = _family == null
        ? _matches
        : _matches.where((Species s) => s.family == _family).toList();
  }
}
