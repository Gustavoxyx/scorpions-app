import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/app_environment.dart';
import '../../firebase_options.dart';

/// Inicialização do Firebase (ETAPAS 2, 9 e 15).
///
/// Fica atrás de uma função única para que `main.dart` continue mínimo e para
/// que exista **um** lugar onde a conexão com a infraestrutura é decidida.
abstract final class FirebaseBootstrap {
  static bool _initialized = false;

  /// Sobe o Firebase conforme o modo do build.
  ///
  /// Em [DataSourceMode.mock] não faz nada: o aplicativo roda sem tocar em
  /// rede, que é o comportamento das Fases 1 e 2 e dos testes de widget.
  static Future<void> ensureInitialized() async {
    if (_initialized || !AppEnvironmentConfig.useFirebase) return;

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (AppEnvironmentConfig.dataSource.isEmulator) {
      await _connectEmulators();
    } else {
      await _activateAppCheck();
    }

    // Persistência offline (§27).
    //
    // Ligada de propósito: com ela, o histórico e o catálogo continuam
    // visíveis sem rede, e uma escrita feita offline é enviada quando a
    // conexão volta. É o que evita o aplicativo "travar" num ônibus sem sinal.
    //
    // No emulador fica desligada para que cada execução comece limpa e um
    // cache antigo não mascare um problema de regra.
    if (!AppEnvironmentConfig.dataSource.isEmulator) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    }

    _initialized = true;
  }

  /// Aponta os SDKs para os emuladores locais.
  static Future<void> _connectEmulators() async {
    const String host = AppEnvironmentConfig.emulatorHost;

    await FirebaseAuth.instance.useAuthEmulator(
      host,
      AppEnvironmentConfig.authEmulatorPort,
    );
    FirebaseFirestore.instance.useFirestoreEmulator(
      host,
      AppEnvironmentConfig.firestoreEmulatorPort,
    );
    await FirebaseStorage.instance.useStorageEmulator(
      host,
      AppEnvironmentConfig.storageEmulatorPort,
    );

    debugPrint('[Scorpions] conectado aos emuladores em $host');
  }

  /// Ativa o App Check (§17).
  ///
  /// # O que ele faz
  /// Atesta que a requisição veio de uma instalação legítima do aplicativo, e
  /// não de um script apontando para o mesmo backend. Reduz abuso de cota e
  /// raspagem do catálogo.
  ///
  /// # O que ele NÃO faz
  /// Não autentica ninguém e não autoriza nada. Um atacante que roube um token
  /// de App Check continua barrado pelas Security Rules, porque elas conferem
  /// `request.auth.uid`. App Check é camada adicional — o brief §17 é explícito
  /// nisso, e é a leitura correta.
  ///
  /// # Provedores
  /// Em depuração usa o provedor de debug, que imprime um token para registrar
  /// no console. Em produção, Play Integrity no Android e App Attest no iOS.
  /// O reCAPTCHA da web precisa de uma chave de site, criada junto do projeto
  /// real — enquanto ela não existir, a web fica sem App Check em vez de
  /// falhar a inicialização.
  static Future<void> _activateAppCheck() async {
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
        providerApple: kDebugMode
            ? const AppleDebugProvider()
            : const AppleAppAttestProvider(),
      );
    } catch (error) {
      // App Check indisponível não pode impedir o aplicativo de abrir: as
      // regras continuam protegendo os dados.
      debugPrint('[Scorpions] App Check não ativado: $error');
    }
  }
}
