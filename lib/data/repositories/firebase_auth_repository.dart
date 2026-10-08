import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../models/app_user.dart';
import '../models/user_role.dart';
import '../services/failure.dart';
import '../services/firebase_bootstrap.dart';
import '../services/firebase_error_mapper.dart';
import '../services/firestore_write_mapper.dart';
import 'auth_repository.dart';

/// Autenticação real (brief §4, §5).
///
/// # A conta vive em dois lugares
/// O Firebase Authentication guarda a credencial (e só ele — a senha nunca
/// passa por este código nem pelo Firestore). O documento `users/{uid}` guarda
/// o perfil. O `uid` é a ponte, e é o identificador do produto: e-mail muda,
/// `uid` não (§5).
///
/// # O documento de perfil é criado de forma idempotente
/// Um cadastro pode falhar entre criar a credencial e criar o documento —
/// queda de rede no meio, por exemplo. Se isso acontecer, a pessoa fica com
/// login válido e sem perfil. Por isso [_ensureProfile] roda também no login:
/// qualquer sessão sem documento o cria na hora, e o estado se conserta
/// sozinho em vez de deixar a conta quebrada para sempre.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    fb.FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? fb.FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance {
    // Encadeia: mudou a sessão -> busca o perfil -> emite o AppUser.
    _subscription = _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  final fb.FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  final StreamController<AppUser?> _controller =
      StreamController<AppUser?>.broadcast();

  late final StreamSubscription<fb.User?> _subscription;

  AppUser? _current;

  /// Nome digitado no cadastro, reservado até o documento existir.
  ///
  /// `createUserWithEmailAndPassword` já deixa o usuário autenticado, e
  /// `_onAuthStateChanged` dispara nesse instante — antes de
  /// `updateDisplayName` completar a ida ao servidor. Sem esta reserva era o
  /// ouvinte que criava o documento, com o nome derivado do e-mail, e o
  /// `signUp` encontrava o documento pronto e devolvia o nome errado. O que a
  /// pessoa digitou sumia sem erro nenhum — e ficava assim, porque o
  /// aplicativo ainda não tem tela para renomear.
  String? _pendingName;

  /// A versão do aviso aceita no cadastro em andamento. Mesma razão de
  /// [_pendingName]: o perfil pode ser criado pelo ouvinte de sessão antes de
  /// `signUp` chegar lá.
  String? _pendingPrivacyVersion;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  @override
  AppUser? get currentUser => _current;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    return FirebaseErrorMapper.guard(() async {
      final fb.UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final fb.User user = _requireUser(credential.user);
      // Conserta uma conta que ficou sem documento (ver nota da classe).
      return _ensureProfile(user, fallbackName: _nameFromEmail(user.email));
    });
  }

  @override
  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
    String? privacyVersion,
  }) async {
    _pendingName = name.trim();
    _pendingPrivacyVersion = privacyVersion;
    try {
      return await FirebaseErrorMapper.guard(() async {
        final fb.UserCredential credential =
            await _auth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        final fb.User user = _requireUser(credential.user);

        // O nome vai para o Authentication também: assim ele sobrevive mesmo
        // que o documento precise ser recriado.
        await user.updateDisplayName(name.trim());

        // Pede a confirmação do endereço já no cadastro (MEDIUM-3).
        //
        // Dentro de um `try` próprio, e sem propagar: se o envio falhar — cota
        // de e-mail do projeto, rede oscilando —, a conta já foi criada e a
        // pessoa precisa conseguir entrar. Falhar o cadastro aqui deixaria uma
        // conta existente atrás de uma tela dizendo que ela não foi criada. O
        // aviso em "Meus dados" continua lá, com o botão de reenviar.
        try {
          await user.sendEmailVerification();
        } catch (_) {
          // Deliberadamente silencioso — ver acima.
        }

        return _ensureProfile(user, fallbackName: name.trim());
      });
    } finally {
      _pendingName = null;
      _pendingPrivacyVersion = null;
    }
  }

  @override
  Future<void> sendPasswordReset(String email) {
    return FirebaseErrorMapper.guard(
      () => _auth.sendPasswordResetEmail(email: email.trim()),
    );
  }

  @override
  Future<void> signOut() {
    return FirebaseErrorMapper.guard(() async {
      await _auth.signOut();

      // Encerrar a sessão não bastava: o Firestore guarda em disco tudo que
      // foi lido — perfil e histórico — e esses arquivos continuavam lá
      // depois da saída. As Security Rules barram o acesso pela rede, não o
      // arquivo que já está no aparelho.
      //
      // Vem depois do `signOut` de propósito. Limpar primeiro deixaria uma
      // janela com a sessão ainda viva e o cache vazio, e qualquer ouvinte
      // ativo repopularia o que acabou de ser apagado.
      await FirebaseBootstrap.clearLocalCache();
    });
  }

  @override
  Future<void> sendEmailVerification() {
    return FirebaseErrorMapper.guard(() async {
      final fb.User? user = _auth.currentUser;
      if (user == null) {
        throw const AppFailure(
          kind: FailureKind.authentication,
          message: 'Entre na sua conta para reenviar a confirmação.',
          code: 'no-current-user',
        );
      }
      if (user.emailVerified) return;
      await user.sendEmailVerification();
    });
  }

  @override
  Future<AppUser?> reload() {
    return FirebaseErrorMapper.guard(() async {
      final fb.User? user = _auth.currentUser;
      if (user == null) return null;

      // A confirmação acontece FORA do aplicativo, num navegador. O objeto em
      // memória não sabe, e sem este `reload` a tela continuaria pedindo para
      // confirmar algo já confirmado — o tipo de aviso que ensina o usuário a
      // ignorar avisos.
      await user.reload();

      final fb.User? atualizado = _auth.currentUser;
      if (atualizado == null) return null;

      // As Security Rules leem `email_verified` do ID token, não deste objeto.
      // O token em uso foi emitido antes da confirmação e só se renova sozinho
      // dentro de uma hora — sem forçar a troca aqui, a pessoa confirmaria o
      // e-mail e continuaria sendo recusada pelo servidor.
      if (atualizado.emailVerified) {
        await atualizado.getIdToken(true);
      }

      final AppUser perfil = await _ensureProfile(
        atualizado,
        fallbackName: _nameFromEmail(atualizado.email),
      );
      _emit(perfil);
      return perfil;
    });
  }

  @override
  Future<void> reauthenticate(String password) {
    return FirebaseErrorMapper.guard(() async {
      final fb.User? user = _auth.currentUser;
      final String? email = user?.email;
      if (user == null || email == null || email.isEmpty) {
        throw const AppFailure(
          kind: FailureKind.authentication,
          message: 'Entre na sua conta para continuar.',
          code: 'no-current-user',
        );
      }

      // O efeito que importa não é o retorno: é mover a claim `auth_time` do
      // próximo ID token. É nela que o servidor olha para decidir se a senha
      // foi apresentada agora, e é o que permite exigir confirmação para uma
      // operação irreversível sem inventar um mecanismo de sessão próprio.
      await user.reauthenticateWithCredential(
        fb.EmailAuthProvider.credential(email: email, password: password),
      );
    });
  }

  @override
  Future<String?> idToken({bool forceRefresh = false}) {
    return FirebaseErrorMapper.guard(
      () async => _auth.currentUser?.getIdToken(forceRefresh),
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    _controller.close();
  }

  // -- Interno ----------------------------------------------------------------

  Future<void> _onAuthStateChanged(fb.User? user) async {
    if (user == null) {
      _emit(null);
      return;
    }
    try {
      // Se um cadastro está em curso, o nome digitado vale mais que o
      // derivado do e-mail — seja qual for o caminho que criar o documento.
      _emit(await _ensureProfile(
        user,
        fallbackName: _pendingName ?? _nameFromEmail(user.email),
      ));
    } on AppFailure {
      // Falha ao ler o perfil não pode derrubar a sessão. Emitimos o que dá
      // para saber a partir do Authentication e a tela segue funcionando; a
      // próxima leitura tenta de novo.
      _emit(_fromFirebaseUser(user));
    }
  }

  /// Lê o documento do usuário; cria se não existir.
  Future<AppUser> _ensureProfile(
    fb.User user, {
    required String fallbackName,
  }) async {
    final DocumentReference<Map<String, dynamic>> ref = _users.doc(user.uid);
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await ref.get();

    // `emailVerified` é sobreposto ao que veio do documento, nos dois retornos.
    //
    // O documento não guarda esse campo — de propósito, para o cliente não ter
    // o que forjar — e `fromMap` o deixa em `false`. Sem esta sobreposição, o
    // aviso de "confirme seu e-mail" apareceria para sempre, inclusive para
    // quem já confirmou: exatamente o aviso-que-não-some que ensina a ignorar
    // avisos. Quem sabe a resposta é o Authentication.
    if (snapshot.exists) {
      return AppUser.fromMap(user.uid, snapshot.data() ?? <String, dynamic>{})
          .copyWith(emailVerified: user.emailVerified);
    }

    final AppUser profile = AppUser(
      id: user.uid,
      name: (user.displayName?.trim().isNotEmpty ?? false)
          ? user.displayName!.trim()
          : fallbackName,
      email: user.email ?? '',
      privacyVersion: _pendingPrivacyVersion,
    );

    await ref.set(FirestoreWriteMapper.prepare(profile.toCreateMap()));

    // Relê para receber os carimbos resolvidos pelo servidor.
    final DocumentSnapshot<Map<String, dynamic>> created = await ref.get();
    return AppUser.fromMap(user.uid, created.data() ?? <String, dynamic>{})
        .copyWith(emailVerified: user.emailVerified);
  }

  /// Perfil mínimo derivado apenas do Authentication.
  ///
  /// Usado como rede de segurança quando o Firestore está indisponível. O
  /// papel cai para [UserRole.user] — falhar para o menos privilegiado.
  AppUser _fromFirebaseUser(fb.User user) {
    return AppUser(
      id: user.uid,
      name: user.displayName?.trim().isNotEmpty ?? false
          ? user.displayName!.trim()
          : _nameFromEmail(user.email),
      email: user.email ?? '',
      role: UserRole.user,
      // Vem do Authentication, que é quem conhece este fato. Guardá-lo no
      // documento criaria uma segunda verdade, escrevível pelo cliente.
      emailVerified: user.emailVerified,
    );
  }

  fb.User _requireUser(fb.User? user) {
    if (user != null) return user;
    throw const AppFailure(
      kind: FailureKind.authentication,
      message: 'Não foi possível concluir o acesso. Tente novamente.',
      code: 'null-user',
    );
  }

  void _emit(AppUser? user) {
    _current = user;
    if (!_controller.isClosed) _controller.add(user);
  }

  static String _nameFromEmail(String? email) {
    if (email == null || email.isEmpty) return 'Usuário';
    final String local = email.split('@').first.replaceAll(RegExp(r'[._-]+'), ' ');
    final String name = local
        .split(' ')
        .where((String part) => part.isNotEmpty)
        .map((String part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
    return name.isEmpty ? 'Usuário' : name;
  }
}
