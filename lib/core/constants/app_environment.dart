/// De onde os dados vêm nesta execução.
///
/// É o eixo da migração gradual pedida no brief §22 e §42: o aplicativo
/// continua inteiro funcionando enquanto trocamos as implementações, porque a
/// escolha acontece num único lugar (o *composition root* em `app/app.dart`) e
/// nenhuma tela sabe qual modo está ativo.
enum DataSourceMode {
  /// Tudo em memória. Não toca em rede. É o modo das Fases 1 e 2 e continua
  /// sendo o que roda nos testes de widget.
  mock('mock'),

  /// Firebase apontado para o Emulator Suite local.
  ///
  /// Usa um `projectId` com prefixo `demo-`, que os SDKs tratam como offline:
  /// mesmo que existam credenciais na máquina, nada alcança a nuvem. É o modo
  /// de desenvolvimento seguro (§20).
  emulator('emulator'),

  /// Firebase real. Exige `firebase_options.dart` gerado por
  /// `flutterfire configure`.
  firebase('firebase');

  const DataSourceMode(this.id);

  final String id;

  bool get usesFirebase => this != DataSourceMode.mock;
  bool get isEmulator => this == DataSourceMode.emulator;

  static DataSourceMode fromId(String raw) {
    for (final DataSourceMode mode in DataSourceMode.values) {
      if (mode.id == raw) return mode;
    }
    return DataSourceMode.mock;
  }
}

/// Ambiente de execução (brief §33).
///
/// Existe para impedir a confusão mais cara que um projeto pode ter: rodar um
/// teste contra o banco de produção. O ambiente é escolhido em tempo de
/// compilação e o `projectId` de cada um é distinto.
enum AppEnvironment {
  development('development'),
  staging('staging'),
  production('production');

  const AppEnvironment(this.id);

  final String id;

  bool get isProduction => this == AppEnvironment.production;

  static AppEnvironment fromId(String raw) {
    for (final AppEnvironment env in AppEnvironment.values) {
      if (env.id == raw) return env;
    }
    return AppEnvironment.development;
  }
}

/// Configuração de infraestrutura resolvida em tempo de compilação.
///
/// # Nada aqui é segredo (§32)
/// Chaves do Firebase para cliente (`apiKey`, `appId`) **não são credenciais**:
/// elas identificam o projeto, não autorizam nada. Quem autoriza é o
/// Authentication mais as Security Rules. Por isso podem viver no binário.
///
/// O que **nunca** pode entrar aqui: service account, chave privada, segredo
/// de API de terceiros, credencial do Firebase Admin. Qualquer operação que
/// precise disso roda em backend.
abstract final class AppEnvironmentConfig {
  /// `--dart-define=DATA_SOURCE=mock|emulator|firebase`
  static final DataSourceMode dataSource = DataSourceMode.fromId(
    const String.fromEnvironment('DATA_SOURCE', defaultValue: 'mock'),
  );

  /// `--dart-define=APP_ENV=development|staging|production`
  static final AppEnvironment environment = AppEnvironment.fromId(
    const String.fromEnvironment('APP_ENV', defaultValue: 'development'),
  );

  /// Host dos emuladores. `localhost` no desktop e no navegador; num aparelho
  /// físico precisa ser o IP da máquina na rede local.
  static const String emulatorHost =
      String.fromEnvironment('EMULATOR_HOST', defaultValue: 'localhost');

  static const int authEmulatorPort = 9099;
  static const int firestoreEmulatorPort = 8080;
  static const int storageEmulatorPort = 9199;

  /// Ligado só quando há infraestrutura real por trás.
  static bool get useFirebase => dataSource.usesFirebase;

  /// Rótulo exibido na tela "Sobre", para que nunca haja dúvida sobre contra o
  /// que o aplicativo está falando.
  static String get label => switch (dataSource) {
        DataSourceMode.mock => 'Dados simulados',
        DataSourceMode.emulator => 'Emulador local (${environment.id})',
        DataSourceMode.firebase => 'Firebase (${environment.id})',
      };
}
