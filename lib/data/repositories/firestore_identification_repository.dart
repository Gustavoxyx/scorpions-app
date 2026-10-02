import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../models/identification.dart';
import '../services/failure.dart';
import '../services/firebase_error_mapper.dart';
import '../services/firestore_write_mapper.dart';
import '../services/image_upload_service.dart';
import 'identification_repository.dart';

/// Histórico de identificações no Firestore (brief §11, §28).
///
/// # A consulta é sempre restrita ao dono
/// Toda leitura filtra por `userId == uid`. Isso não é apenas boa prática: as
/// Security Rules **exigem** o filtro — uma consulta sem ele é recusada pelo
/// servidor. As duas camadas dizem a mesma coisa, e a de baixo é a que vale.
///
/// # Ordem das operações ao salvar
/// 1. imagem sobe para o Storage;
/// 2. documento é gravado com a URL.
///
/// Nessa ordem, um documento nunca aponta para um arquivo inexistente. O caso
/// contrário — arquivo sem documento, se a gravação falhar depois do upload —
/// gera um órfão, que é o problema mais barato dos dois e será varrido por uma
/// Function de limpeza.
class FirestoreIdentificationRepository implements IdentificationRepository {
  FirestoreIdentificationRepository({
    FirebaseFirestore? firestore,
    fb.FirebaseAuth? auth,
    required ImageUploadService uploader,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? fb.FirebaseAuth.instance,
        // A regra sugere `this._uploader`, mas Dart não aceita parâmetro
        // nomeado com nome privado. Manter o campo público só para satisfazer
        // o lint seria pior: exporia a dependência.
        // ignore: prefer_initializing_formals
        _uploader = uploader;

  final FirebaseFirestore _firestore;
  final fb.FirebaseAuth _auth;
  final ImageUploadService _uploader;

  /// Teto de leitura por consulta.
  ///
  /// Existe para que o histórico de um usuário antigo não baixe milhares de
  /// documentos numa aba. A paginação real entra quando houver necessidade —
  /// a assinatura do repositório já comporta.
  static const int _pageLimit = 100;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('identifications');

  String get _uid {
    final String? uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const AppFailure(
        kind: FailureKind.authentication,
        message: 'Sua sessão expirou. Entre novamente.',
        code: 'unauthenticated',
      );
    }
    return uid;
  }

  @override
  Future<List<IdentificationResult>> fetchHistory() {
    return FirebaseErrorMapper.guard(() async {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await _collection
          .where('userId', isEqualTo: _uid)
          .orderBy('createdAt', descending: true)
          .limit(_pageLimit)
          .get();

      return snapshot.docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
              IdentificationResult.fromMap(doc.id, doc.data()))
          .toList(growable: false);
    });
  }

  @override
  Future<IdentificationResult?> findById(String id) {
    return FirebaseErrorMapper.guard(() async {
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await _collection.doc(id).get();
      if (!doc.exists) return null;
      return IdentificationResult.fromMap(doc.id, doc.data() ?? <String, dynamic>{});
    });
  }

  @override
  Future<void> save(IdentificationResult result) {
    return FirebaseErrorMapper.guard(() async {
      final String uid = _uid;

      // Este repositório **não envia imagem**. Quem envia é o
      // `IdentificationPipeline`, e depois liga os caminhos com
      // [attachImages].
      //
      // Antes a gravação tentava enviar por conta própria, e o resultado era um
      // envio duplicado do original: o pipeline já mandava as três formas logo
      // em seguida. Persistir e transferir arquivo são trabalhos diferentes, e
      // misturar os dois cobrou a banda do usuário duas vezes.
      final IdentificationResult owned = result.copyWith(userId: uid);

      await _collection
          .doc(result.id)
          .set(FirestoreWriteMapper.prepare(owned.toMap()));
    });
  }

  @override
  Future<void> attachImages(
    String id, {
    String? imageUrl,
    String? thumbnailUrl,
  }) {
    return FirebaseErrorMapper.guard(() async {
      // `update` e não `set`: toca só estes campos. O documento inteiro traria
      // um `createdAt` novo junto, e a regra de segurança exige que ele não
      // mude depois da criação.
      await _collection.doc(id).update(<String, Object?>{
        'imageUrl': ?imageUrl,
        'thumbnailUrl': ?thumbnailUrl,
      });
    });
  }

  @override
  Future<void> delete(String id) {
    return FirebaseErrorMapper.guard(() async {
      final String uid = _uid;

      // Apaga o arquivo antes do documento: enquanto o documento existir, o
      // usuário ainda consegue ver e reagir se a remoção falhar no meio.
      // Falha ao apagar a imagem não impede a remoção do registro — um arquivo
      // órfão é preferível a um registro que o usuário não consegue apagar.
      await _uploader.deleteFor(userId: uid, identificationId: id);
      await _collection.doc(id).delete();
    });
  }
}
