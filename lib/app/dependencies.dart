import '../core/constants/app_environment.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/firebase_auth_repository.dart';
import '../data/repositories/firestore_identification_repository.dart';
import '../data/repositories/firestore_species_repository.dart';
import '../data/repositories/identification_repository.dart';
import '../data/repositories/mock_auth_repository.dart';
import '../data/repositories/species_repository.dart';
import '../data/services/image_upload_service.dart';

/// Raiz de composição: onde as implementações concretas são escolhidas.
///
/// # Por que existe um arquivo só para isto (brief §22, §23, §42)
/// A migração MOCK → Firebase precisa ser gradual e reversível. Concentrando a
/// escolha aqui, trocar de infraestrutura é mudar uma variável de build — não
/// editar dezenas de telas. E se algo der errado com o Firebase, voltar ao
/// modo simulado é imediato:
///
///     flutter run --dart-define=DATA_SOURCE=mock       # em memória
///     flutter run --dart-define=DATA_SOURCE=emulator   # emuladores locais
///     flutter run --dart-define=DATA_SOURCE=firebase   # nuvem
///
/// Nenhuma tela, nenhum controlador e nenhum widget sabe qual modo está ativo.
/// Todos falam com as interfaces em `data/repositories/` e `data/services/`.
class AppDependencies {
  AppDependencies._({
    required this.authRepository,
    required this.speciesRepository,
    required this.identificationRepository,
    required this.imageUploadService,
    required this.mode,
  });

  /// Monta o conjunto de dependências do modo configurado no build.
  factory AppDependencies.resolve() {
    final DataSourceMode mode = AppEnvironmentConfig.dataSource;

    if (!mode.usesFirebase) {
      // Modo simulado: nada toca a rede.
      const ImageUploadService uploader = NoopImageUploadService();
      return AppDependencies._(
        authRepository: MockAuthRepository(),
        speciesRepository: const MockSpeciesRepository(),
        identificationRepository: InMemoryIdentificationRepository(),
        imageUploadService: uploader,
        mode: mode,
      );
    }

    // `emulator` e `firebase` usam exatamente as mesmas implementações: a
    // diferença é só para onde os SDKs apontam, decidida em
    // `FirebaseBootstrap`. É o que garante que testar no emulador exercite o
    // mesmo código que roda em produção.
    final ImageUploadService uploader = FirebaseImageUploadService();

    return AppDependencies._(
      authRepository: FirebaseAuthRepository(),
      speciesRepository: FirestoreSpeciesRepository(),
      identificationRepository: FirestoreIdentificationRepository(
        uploader: uploader,
      ),
      imageUploadService: uploader,
      mode: mode,
    );
  }

  /// Conjunto explicitamente simulado, para testes.
  factory AppDependencies.mock() {
    return AppDependencies._(
      authRepository: MockAuthRepository(),
      speciesRepository: const MockSpeciesRepository(),
      identificationRepository: InMemoryIdentificationRepository(),
      imageUploadService: const NoopImageUploadService(),
      mode: DataSourceMode.mock,
    );
  }

  final AuthRepository authRepository;
  final SpeciesRepository speciesRepository;
  final IdentificationRepository identificationRepository;
  final ImageUploadService imageUploadService;
  final DataSourceMode mode;

  /// Rótulo exibido na tela "Sobre", para nunca haver dúvida sobre contra qual
  /// infraestrutura o aplicativo está falando.
  String get label => AppEnvironmentConfig.label;
}
