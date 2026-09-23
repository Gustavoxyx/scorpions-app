import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../models/app_user.dart';
import '../models/user_role.dart';
import '../services/failure.dart';
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
  }) async {
    return FirebaseErrorMapper.guard(() async {
      final fb.UserCredential credential =
          await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final fb.User user = _requireUser(credential.user);

      // O nome vai para o Authentication também: assim ele sobrevive mesmo que
      // o documento precise ser recriado.
      await user.updateDisplayName(name.trim());

      return _ensureProfile(user, fallbackName: name.trim());
    });
  }

  @override
  Future<void> sendPasswordReset(String email) {
    return FirebaseErrorMapper.guard(
      () => _auth.sendPasswordResetEmail(email: email.trim()),
    );
  }

  @override
  Future<void> signOut() => FirebaseErrorMapper.guard(() => _auth.signOut());

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
      _emit(await _ensureProfile(user, fallbackName: _nameFromEmail(user.email)));
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

    if (snapshot.exists) {
      return AppUser.fromMap(user.uid, snapshot.data() ?? <String, dynamic>{});
    }

    final AppUser profile = AppUser(
      id: user.uid,
      name: (user.displayName?.trim().isNotEmpty ?? false)
          ? user.displayName!.trim()
          : fallbackName,
      email: user.email ?? '',
    );

    await ref.set(FirestoreWriteMapper.prepare(profile.toCreateMap()));

    // Relê para receber os carimbos resolvidos pelo servidor.
    final DocumentSnapshot<Map<String, dynamic>> created = await ref.get();
    return AppUser.fromMap(user.uid, created.data() ?? <String, dynamic>{});
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
