/// Papel do usuário no produto (brief §6).
///
/// # Por que é um enum fechado, e pequeno
/// Começa com dois valores porque só dois são necessários hoje. Os papéis
/// previstos para o futuro (`researcher`, `reviewer`) estão declarados mas
/// desabilitados: assim o vocabulário já existe e as regras de segurança podem
/// ser escritas contra ele, sem que a aplicação finja ter permissões que ainda
/// não sabe conceder.
///
/// # Onde este valor é confiável
/// **Não aqui.** O `role` que chega ao aplicativo vem do documento
/// `users/{uid}` e serve apenas para a interface decidir o que mostrar. A
/// autorização real acontece nas Security Rules do Firestore, que leem o mesmo
/// documento no servidor (§7, §38). Um cliente adulterado pode mentir sobre o
/// próprio papel para si mesmo — e não vai conseguir escrever nada por isso.
enum UserRole {
  /// Usuário comum: lê o catálogo, cria e gerencia as próprias identificações.
  user('user', enabled: true),

  /// Administrador: gerencia espécies e conteúdo do catálogo.
  admin('admin', enabled: true),

  /// Previsto: contribui com identificações revisadas. Ainda sem permissões.
  researcher('researcher', enabled: false),

  /// Previsto: valida identificações de terceiros (human-in-the-loop, Fase 8).
  reviewer('reviewer', enabled: false);

  const UserRole(this.id, {required this.enabled});

  /// Valor persistido no Firestore. Nunca use `name` do enum diretamente:
  /// renomear o membro em Dart não pode invalidar dados já gravados.
  final String id;

  /// Se `false`, o papel existe como vocabulário mas não concede nada ainda.
  final bool enabled;

  bool get isAdmin => this == UserRole.admin;

  String get label => switch (this) {
        UserRole.user => 'Usuário',
        UserRole.admin => 'Administrador',
        UserRole.researcher => 'Pesquisador',
        UserRole.reviewer => 'Revisor',
      };

  /// Converte o valor vindo do banco.
  ///
  /// Desconhecido vira [UserRole.user] — a falha é para o **menos**
  /// privilegiado. Um documento corrompido ou de uma versão futura do app
  /// jamais deve resultar em privilégio elevado.
  static UserRole fromId(Object? raw) {
    if (raw is! String) return UserRole.user;
    for (final UserRole role in UserRole.values) {
      if (role.id == raw) return role;
    }
    return UserRole.user;
  }
}
