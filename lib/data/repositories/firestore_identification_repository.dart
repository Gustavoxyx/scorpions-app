import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';

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

      // 1. Imagem primeiro (ver nota da classe).
      String? imageUrl = result.imageUrl;
      if (imageUrl == null && result.image.isUploadable) {
        imageUrl = await _uploadOrSkip(uid: uid, result: result);
      }

      // 2. Documento com a referência já resolvida.
      final IdentificationResult owned =
          result.copyWith(userId: uid, imageUrl: imageUrl);

      await _collection
          .doc(result.id)
          .set(FirestoreWriteMapper.prepare(owned.toMap()));
    });
  }

  /// Tenta enviar a imagem; devolve `null` se não der.
  ///
  /// # Por que a falha de upload não derruba o salvamento
  /// A identificação vale mais que a fotografia. Se o Storage estiver
  /// indisponível — sem rede no meio do envio, cota estourada, ou o bucket
  /// simplesmente não provisionado — o usuário perderia o resultado inteiro
  /// por causa de um anexo. O registro é gravado sem imagem e o histórico
  /// continua correto; `imageUrl` nulo já é um estado que a UI sabe desenhar,
  /// porque é o mesmo caso do modo simulado.
  ///
  /// Isto também é o que permite rodar no plano gratuito do Firebase, onde o
  /// Cloud Storage não está disponível: Auth e Firestore funcionam, e as fotos
  /// ficam para quando houver bucket.
  ///
  /// Erros de **validação** são a exceção e sobem: uma imagem corrompida ou
  /// grande demais é problema que o usuário pode corrigir, e silenciá-lo o
  /// deixaria sem saber por que a foto sumiu.
  Future<String?> _uploadOrSkip({
    required String uid,
    required IdentificationResult result,
  }) async {
    try {
      return await _uploader.upload(
        image: result.image,
        userId: uid,
        identificationId: result.id,
      );
    } on AppFailure catch (failure) {
      if (failure.kind == FailureKind.validation) rethrow;
      debugPrint(
        '[Scorpions] imagem não enviada (${failure.code}); '
        'a identificação será salva sem foto.',
      );
      return null;
    }
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
