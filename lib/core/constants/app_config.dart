/// Configuração de build e chaves de comportamento.
///
/// SEGURANÇA: este arquivo NUNCA deve conter segredos, chaves de API, tokens
/// ou credenciais. Valores sensíveis entram por `--dart-define` na Fase 3 e
/// ficam no backend, nunca no binário do cliente.
abstract final class AppConfig {
  static const String appName = 'Scorpions';

  /// Nome de trabalho: aponta direto ao objeto de estudo e é legível sem
  /// que o usuário já conheça a anatomia do animal.
  ///
  /// (O nome anterior era *Telson*, o último segmento da cauda. O termo
  /// continua no código — `AnatomyPart.telson` —, mas como anatomia, não
  /// como marca.)
  static const String appTagline = 'Identificação científica de escorpiões';

  static const String version = '0.2.0';
  static const String phaseLabel = 'Fase 2 · Identidade visual';

  /// Abre o aplicativo já autenticado, pulando onboarding e login.
  ///
  /// Desligado por padrão. Serve para dois usos legítimos:
  /// apresentar o produto sem repetir o cadastro a cada abertura, e capturar
  /// telas internas durante o desenvolvimento.
  ///
  ///     flutter run --dart-define=DEMO_AUTOLOGIN=true
  ///
  /// Não é um atalho de autenticação: quando o Firebase entrar na Fase 3, o
  /// caminho real de login passa a ser o único que produz uma sessão válida, e
  /// este sinalizador continua servindo apenas ao repositório simulado.
  static const bool demoAutoLogin = bool.fromEnvironment('DEMO_AUTOLOGIN');

  /// Tema inicial do build: `light` (padrão), `dark` ou `system`.
  ///
  ///     flutter run --dart-define=DEMO_THEME=dark
  ///
  /// Existe para inspecionar e apresentar os dois temas sem passar pelas
  /// Configurações a cada abertura. O usuário continua podendo trocar o tema
  /// pela interface; isto define apenas o ponto de partida.
  static const String initialTheme =
      String.fromEnvironment('DEMO_THEME', defaultValue: 'light');

  /// FASE 1: toda identificação é simulada. Este sinalizador controla o banner
  /// de dados fictícios exibido na UI e será desligado quando a IA real entrar.
  static const bool useMockIdentification = true;

  /// FASE 1: autenticação local em memória. Vira `false` na Fase 3 (Firebase).
  static const bool useMockAuth = true;

  /// Duração simulada da análise. Some quando o modelo real assumir.
  static const Duration mockAnalysisDuration = Duration(milliseconds: 4200);

  /// Limiares de confiança do produto. A IA da Fase 5 deve respeitá-los.
  static const double highConfidenceThreshold = 0.85;
  static const double mediumConfidenceThreshold = 0.65;

  /// Abaixo deste valor o sistema deve responder "não sei" em vez de arriscar.
  static const double rejectionThreshold = 0.45;
}
