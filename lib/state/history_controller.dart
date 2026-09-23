import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/app_user.dart';
import '../data/models/identification.dart';
import '../data/repositories/identification_repository.dart';
import '../data/services/failure.dart';

/// Estado da aba Histórico (brief §26, §27, §28).
///
/// # Por que ele escuta o usuário
/// O histórico é sempre o histórico *de alguém*. Ao trocar de sessão — entrar,
/// sair, ou o token expirar — a lista precisa ser recarregada; caso contrário
/// o próximo usuário veria, por um instante, os registros do anterior. Isso
/// não é só desconforto visual: é vazamento de dado entre contas no mesmo
/// aparelho.
class HistoryController extends ChangeNotifier {
  HistoryController(this._repository, {Stream<AppUser?>? authChanges}) {
    if (authChanges != null) {
      _authSubscription = authChanges.listen(_onUserChanged);
    } else {
      unawaited(refresh());
    }
  }

  final IdentificationRepository _repository;
  StreamSubscription<AppUser?>? _authSubscription;

  /// Dono da lista carregada. Usado para descartar respostas fora de ordem.
  String? _loadedFor;

  List<IdentificationResult> _items = <IdentificationResult>[];
  List<IdentificationResult> get items => _items;

  bool _loading = true;
  bool get loading => _loading;

  /// Mensagem já traduzida, quando a carga falha (§25).
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool get hasError => _errorMessage != null;

  /// `true` quando faz sentido oferecer "tentar novamente".
  bool _retryable = false;
  bool get isRetryable => _retryable;

  bool get isEmpty => !_loading && !hasError && _items.isEmpty;

  /// Quantidade de espécies distintas já identificadas — usada no perfil.
  int get distinctSpeciesCount => _items
      .where((IdentificationResult r) => !r.isRejected)
      .map((IdentificationResult r) => r.top.species.id)
      .toSet()
      .length;

  Future<void> refresh() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _items = await _repository.fetchHistory();
      _errorMessage = null;
    } on AppFailure catch (failure) {
      // Uma falha de rede não apaga o que já estava na tela: o usuário
      // continua vendo o histórico anterior com um aviso, em vez de encarar
      // uma lista vazia que sugere que perdeu tudo.
      _errorMessage = failure.message;
      _retryable = failure.isRetryable;
    } catch (_) {
      _errorMessage = 'Não foi possível carregar seu histórico.';
      _retryable = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> remove(String id) async {
    try {
      await _repository.delete(id);
      await refresh();
    } on AppFailure catch (failure) {
      _errorMessage = failure.message;
      notifyListeners();
    }
  }

  /// Limpa tudo — usado no logout, antes que outra conta entre.
  void clear() {
    _items = <IdentificationResult>[];
    _errorMessage = null;
    _loading = false;
    _loadedFor = null;
    notifyListeners();
  }

  void _onUserChanged(AppUser? user) {
    if (user == null) {
      clear();
      return;
    }
    if (_loadedFor == user.id) return;
    _loadedFor = user.id;
    unawaited(refresh());
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
