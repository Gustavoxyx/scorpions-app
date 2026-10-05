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

  /// Endereço do backend de inferência e de conta.
  ///
  /// `--dart-define=BACKEND_URL=https://exemplo.com`
  ///
  /// Vazio significa **sem backend**: as telas que dependem dele mostram o
  /// motivo em vez de falhar. Nenhum endereço padrão é assumido — um padrão
  /// apontando para um host que não é nosso mandaria token de usuário para
  /// terceiro.
  static const String backendBaseUrl =
      String.fromEnvironment('BACKEND_URL', defaultValue: '');

  /// Se o backend está configurado **e** o endereço é aceitável.
  static bool get hasBackend => backendBaseUrl.isNotEmpty && isBackendUrlSafe;

  /// O endereço do backend exige TLS, exceto em desenvolvimento local.
  ///
  /// # Por que esta guarda existe
  /// A auditoria de criptografia registrou isto como C-3: o aplicativo manda o
  /// ID token do Firebase no cabeçalho de cada chamada. Em `http://`, esse
  /// token atravessa a rede em texto claro, e quem o capturar passa a agir como
  /// o usuário até ele expirar.
  ///
  /// A exceção é só para desenvolvimento local, onde não há rede para
  /// interceptar: `localhost`, `127.0.0.1` e `[::1]`, e nada além disso. Um
  /// endereço de rede local como `192.168.0.10` **não** entra — ali já existe
  /// rede, e com ela qualquer outro aparelho do mesmo Wi-Fi.
  static bool get isBackendUrlSafe => isUrlSafe(backendBaseUrl);

  /// A mesma verificação, sobre uma URL qualquer.
  ///
  /// Pública porque o cliente HTTP a chama no caminho de cada requisição, e
  /// não só na leitura da configuração: `baseUrl` pode vir pelo construtor, e a
  /// guarda precisa estar por onde o token de fato sai. Ser testável sem
  /// recompilar com outro `--dart-define` é consequência, não o motivo.
  ///
  /// # Por que `Uri`, e não cortar a string
  /// A primeira versão extraía o host à mão — cortava no primeiro `/` e depois
  /// no primeiro `:`. Um teste a derrubou em dois sentidos:
  ///
  /// - `http://[::1]:8000` era **recusado**: o corte no `:` devolvia `[`.
  ///   Incômodo, mas falhava para o lado seguro.
  /// - `http://localhost:80@evil.com` era **aceito**: o corte devolvia
  ///   `localhost`, quando o host de verdade é `evil.com` — `localhost:80` ali é
  ///   usuário e senha. Este falhava para o lado errado, e mandaria o token do
  ///   usuário em texto claro para um host de terceiro.
  ///
  /// Interpretar URL com manipulação de texto é a origem clássica desse tipo de
  /// desvio. `Uri` segue a especificação, e é o mesmo analisador que o cliente
  /// HTTP usa para abrir a conexão — então o que esta função aprova é
  /// exatamente o host para onde o pedido vai.
  static bool isUrlSafe(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;

    // Credencial embutida no endereço nunca é legítima aqui, em nenhum esquema:
    // é o disfarce do segundo caso acima, e o backend autentica por cabeçalho.
    if (uri.userInfo.isNotEmpty) return false;

    if (uri.scheme == 'https') return true;
    if (uri.scheme != 'http') return false;

    // `Uri.host` devolve o IPv6 sem os colchetes.
    return uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host == '::1';
  }

  /// Por que o backend está indisponível, para a tela poder dizer.
  ///
  /// `null` quando está tudo certo. Separar a razão do booleano evita a
  /// mensagem genérica de "algo deu errado", que não ajuda ninguém a corrigir
  /// uma configuração.
  static String? get backendUnavailableReason {
    if (backendBaseUrl.isEmpty) {
      return 'Este recurso precisa do serviço online, que não está '
          'configurado nesta versão do aplicativo.';
    }
    if (!isBackendUrlSafe) {
      // Esta mensagem é para quem compilou, e é neste momento que ela precisa
      // aparecer — não depois, num log que ninguém lê.
      return 'O endereço do serviço precisa usar HTTPS.';
    }
    return null;
  }

  /// Rótulo exibido na tela "Sobre", para que nunca haja dúvida sobre contra o
  /// que o aplicativo está falando.
  static String get label => switch (dataSource) {
        DataSourceMode.mock => 'Dados simulados',
        DataSourceMode.emulator => 'Emulador local (${environment.id})',
        DataSourceMode.firebase => 'Firebase (${environment.id})',
      };
}
