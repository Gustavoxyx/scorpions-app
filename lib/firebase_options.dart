// =============================================================================
// ARQUIVO PROVISÓRIO — gerado à mão, para o Emulator Suite.
// =============================================================================
//
// Normalmente este arquivo é produzido por:
//
//     flutterfire configure
//
// Enquanto não existe um projeto Firebase real, ele aponta para `demo-scorpions`,
// que os SDKs tratam como projeto local: nada aqui alcança a nuvem. Rodar
// `flutterfire configure` sobrescreve este arquivo com os valores reais e
// nenhuma outra linha do projeto precisa mudar.
//
// -----------------------------------------------------------------------------
// ESTES VALORES NÃO SÃO SEGREDOS (brief §32)
// -----------------------------------------------------------------------------
// `apiKey` e `appId` do Firebase para cliente **identificam** o projeto; não
// **autorizam** nada. Eles vão embutidos em todo aplicativo publicado e podem
// ser extraídos de qualquer APK — é assim por projeto do Firebase, não por
// descuido. Quem autoriza é o Authentication mais as Security Rules.
//
// O que NUNCA pode entrar aqui, nem em qualquer arquivo do Flutter:
//   · service account / chave privada
//   · credenciais do Firebase Admin SDK
//   · segredo de API de terceiros
//   · senha de qualquer natureza
//
// Toda operação que exija privilégio administrativo roda em backend.
// =============================================================================

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Opções de conexão por plataforma.
class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS => ios,
      TargetPlatform.macOS => ios,
      TargetPlatform.windows => web,
      _ => web,
    };
  }

  /// Identificador do projeto.
  ///
  /// O prefixo `demo-` é uma convenção reconhecida pelos SDKs e pela CLI: com
  /// ele, os clientes só falam com emuladores. É a salvaguarda que impede um
  /// teste de escrever em produção por engano (§20, §33).
  static const String demoProjectId = 'demo-scorpions';

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: demoProjectId,
    authDomain: 'demo-scorpions.firebaseapp.com',
    storageBucket: 'demo-scorpions.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:android:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: demoProjectId,
    storageBucket: 'demo-scorpions.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:ios:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: demoProjectId,
    storageBucket: 'demo-scorpions.appspot.com',
    iosBundleId: 'com.scorpionslabs.scorpions',
  );
}
