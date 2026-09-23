import '../../core/utils/formatters.dart';
import 'firestore_codec.dart';
import 'user_role.dart';

/// Usuário da aplicação — espelho do documento `users/{uid}`.
///
/// # O UID é o identificador, não o e-mail (§5)
/// O e-mail pode mudar, pode ser reutilizado depois de uma exclusão de conta e
/// não é único ao longo do tempo. O `uid` do Firebase Authentication é estável
/// e é a chave do documento.
///
/// # O que este modelo deliberadamente NÃO carrega (§9, §15)
/// Senha, tokens, telefone, localização ou qualquer dado que o produto não
/// use. Senha pertence ao Authentication e nunca transita por aqui. Minimizar
/// o que se armazena é a forma mais barata de proteger o usuário: dado que não
/// existe não vaza.
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.role = UserRole.user,
    this.avatarUrl,
    this.identificationCount = 0,
    this.speciesSeenCount = 0,
    this.memberSince,
    this.updatedAt,
  });

  /// UID do Firebase Authentication. É a chave do documento no Firestore.
  final String id;

  final String name;
  final String email;

  /// Papel do usuário. Informativo para a UI; a autorização real está nas
  /// Security Rules (ver [UserRole]).
  final UserRole role;

  /// Nulo enquanto não houver foto de perfil; o avatar usa as iniciais.
  final String? avatarUrl;

  /// Contadores denormalizados.
  ///
  /// São mantidos por conveniência de leitura (o perfil não precisa varrer a
  /// coleção de identificações só para mostrar um número). Como toda
  /// denormalização, podem divergir — por isso a fonte de verdade continua
  /// sendo a coleção, e as telas que precisam de exatidão contam de lá.
  final int identificationCount;
  final int speciesSeenCount;

  /// `createdAt` do documento.
  final DateTime? memberSince;
  final DateTime? updatedAt;

  String get firstName => Formatters.firstName(name);
  String get initials => Formatters.initials(name);

  // -- Serialização -----------------------------------------------------------

  /// Lê o documento `users/{uid}`.
  ///
  /// Tolerante a campos ausentes: um documento gravado por uma versão anterior
  /// do app não pode derrubar a tela de perfil.
  factory AppUser.fromMap(String id, Map<String, dynamic> map) {
    return AppUser(
      id: id,
      name: FirestoreCodec.string(map['name']),
      email: FirestoreCodec.string(map['email']),
      role: UserRole.fromId(map['role']),
      avatarUrl: FirestoreCodec.stringOrNull(map['avatarUrl']),
      identificationCount: FirestoreCodec.integer(map['identificationCount']),
      speciesSeenCount: FirestoreCodec.integer(map['speciesSeenCount']),
      memberSince: FirestoreCodec.dateTime(map['createdAt']),
      updatedAt: FirestoreCodec.dateTime(map['updatedAt']),
    );
  }

  /// Campos gravados na **criação** do documento.
  ///
  /// # Por que `role` vai junto, e por que isso é seguro
  /// O papel é sempre escrito como `user`, nunca a partir de [role]. Quem
  /// impede a escalação de privilégio não é esta linha — é a Security Rule,
  /// que exige literalmente `request.resource.data.role == 'user'` na criação.
  /// Um cliente adulterado que enviasse `admin` seria recusado pelo servidor.
  ///
  /// O campo precisa estar presente justamente porque a regra o exige: omiti-lo
  /// faz a comparação virar `null == 'user'` e **todo cadastro falha** com
  /// `permission-denied`. Promover alguém a admin é operação de console.
  Map<String, Object?> toCreateMap() => <String, Object?>{
        'uid': id,
        'name': name,
        'email': email,
        'role': UserRole.user.id,
        'createdAt': FirestoreCodec.serverTimestamp,
        'updatedAt': FirestoreCodec.serverTimestamp,
      };

  /// Campos que o próprio usuário pode alterar depois.
  Map<String, Object?> toUpdateMap() => <String, Object?>{
        'name': name,
        'updatedAt': FirestoreCodec.serverTimestamp,
      };

  AppUser copyWith({
    String? name,
    String? email,
    UserRole? role,
    String? avatarUrl,
    int? identificationCount,
    int? speciesSeenCount,
  }) {
    return AppUser(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      identificationCount: identificationCount ?? this.identificationCount,
      speciesSeenCount: speciesSeenCount ?? this.speciesSeenCount,
      memberSince: memberSince,
      updatedAt: updatedAt,
    );
  }
}
