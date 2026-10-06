import 'package:flutter/foundation.dart';

import '../data/repositories/account_repository.dart';
import '../data/repositories/auth_repository.dart';
import '../data/services/failure.dart';

/// Em que ponto do fluxo de exclusão a tela está.
enum DeletionStage {
  /// Nada em andamento.
  idle,

  /// O servidor pediu a senha. A tela precisa coletá-la.
  awaitingPassword,

  /// A cascata está rodando.
  deleting,

  /// Terminou. A conta não existe mais.
  done,
}

/// Operações sobre a própria conta: exclusão, exportação, cota.
///
/// # Por que a exclusão tem um estado, e não é só um `Future`
/// Porque ela tem **dois passos**, e o segundo depende do primeiro falhar de um
/// jeito específico: o servidor recusa com "digite a senha", a tela coleta a
/// senha, reautentica e tenta de novo.
///
/// Modelar isso como um `Future` que às vezes lança `ReauthenticationRequired`
/// jogaria para a tela a tarefa de lembrar em que ponto estava — e a tela já
/// tem o diálogo, o campo de texto e o botão para cuidar.
class AccountController extends ChangeNotifier {
  // Os nomes públicos são `account:` e `auth:` — o sublinhado fica só nos
  // campos. (Havia aqui uma supressão de lint com um comentário afirmando o
  // contrário. Estava errado, e o lint tinha razão.)
  AccountController({
    required this._account,
    required this._auth,
  });

  final AccountRepository _account;
  final AuthRepository _auth;

  DeletionStage _stage = DeletionStage.idle;
  DeletionStage get stage => _stage;

  AppFailure? _failure;
  AppFailure? get failure => _failure;

  DeletionReceipt? _receipt;
  DeletionReceipt? get receipt => _receipt;

  QuotaSnapshot? _quota;
  QuotaSnapshot? get quota => _quota;

  bool _exporting = false;
  bool get isExporting => _exporting;

  bool get isBusy =>
      _stage == DeletionStage.deleting || _exporting;

  /// Lê a cota de hoje. Silencioso em caso de falha — é informativo.
  Future<void> refreshQuota() async {
    _quota = await _account.quota();
    notifyListeners();
  }

  /// Primeira tentativa de exclusão.
  ///
  /// Normalmente termina em [DeletionStage.awaitingPassword], porque o servidor
  /// exige senha recente para uma operação irreversível. A tela então chama
  /// [confirmDeletion].
  Future<void> requestDeletion() async {
    if (isBusy) return;

    _stage = DeletionStage.deleting;
    _failure = null;
    notifyListeners();

    try {
      _receipt = await _account.deleteAccount();
      _stage = DeletionStage.done;
    } on ReauthenticationRequired {
      // Não é erro: é o próximo passo. Por isso não vira `_failure` — a tela
      // mostraria uma mensagem vermelha onde deveria abrir um campo de senha.
      _stage = DeletionStage.awaitingPassword;
    } on AppFailure catch (erro) {
      _failure = erro;
      _stage = DeletionStage.idle;
    }

    notifyListeners();
  }

  /// Segunda tentativa, com a senha que o usuário acabou de digitar.
  Future<void> confirmDeletion(String password) async {
    if (_stage != DeletionStage.awaitingPassword) return;

    _stage = DeletionStage.deleting;
    _failure = null;
    notifyListeners();

    try {
      await _auth.reauthenticate(password);

      // `forceRefresh: true` não é opcional aqui.
      //
      // Reautenticar move a claim `auth_time`, mas o SDK continua entregando o
      // token em cache — com o `auth_time` antigo. Sem forçar a renovação, o
      // servidor recusaria de novo, e o usuário veria o pedido de senha
      // aparecer uma segunda vez depois de ter digitado a senha certa.
      await _auth.idToken(forceRefresh: true);

      _receipt = await _account.deleteAccount();
      _stage = DeletionStage.done;
    } on ReauthenticationRequired {
      // Chegar aqui significa que o token renovado ainda não satisfez o
      // servidor. É relógio fora de hora no aparelho, quase sempre.
      _failure = const AppFailure(
        kind: FailureKind.authentication,
        message: 'Não foi possível confirmar sua senha. '
            'Verifique a data e a hora do aparelho e tente de novo.',
        code: 'reauth_loop',
      );
      _stage = DeletionStage.idle;
    } on AppFailure catch (erro) {
      _failure = erro;
      // Senha errada volta para o pedido de senha, não para o início: o usuário
      // quer tentar de novo, e mandá-lo recomeçar o fluxo seria punição por
      // erro de digitação.
      _stage = erro.code == 'wrong-password'
          ? DeletionStage.awaitingPassword
          : DeletionStage.idle;
    }

    notifyListeners();
  }

  /// Desiste da exclusão.
  void cancelDeletion() {
    if (_stage == DeletionStage.done) return;
    _stage = DeletionStage.idle;
    _failure = null;
    notifyListeners();
  }

  /// Exporta os dados do titular (Art. 18, V).
  ///
  /// Devolve o pacote, ou `null` se falhou — e nesse caso [failure] diz por quê.
  /// Quem grava o arquivo é a tela: decidir onde salvar é assunto de
  /// plataforma, não de estado.
  Future<Map<String, Object?>?> exportData() async {
    if (isBusy) return null;

    _exporting = true;
    _failure = null;
    notifyListeners();

    try {
      return await _account.exportData();
    } on AppFailure catch (erro) {
      _failure = erro;
      return null;
    } finally {
      _exporting = false;
      notifyListeners();
    }
  }

  void clearFailure() {
    if (_failure == null) return;
    _failure = null;
    notifyListeners();
  }
}
