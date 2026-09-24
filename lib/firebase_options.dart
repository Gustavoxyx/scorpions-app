// =============================================================================
// GERADO POR `flutterfire configure` — não edite à mão.
// =============================================================================
//
// Aponta para o projeto de nuvem `scorpions-tcc-2026`. Para regenerar:
//
//     flutterfire configure --project=scorpions-tcc-2026
//
// As opções do Emulator Suite ficam em `demo_firebase_options.dart`, que esta
// ferramenta não toca. Quem escolhe entre os dois é `FirebaseBootstrap`,
// conforme `--dart-define=DATA_SOURCE`.
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

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCeUs7TVfXdLcFBt7mGtE0YwNtufG3BSmo',
    appId: '1:305720226190:web:601f0a127114c65312f4df',
    messagingSenderId: '305720226190',
    projectId: 'scorpions-tcc-2026',
    authDomain: 'scorpions-tcc-2026.firebaseapp.com',
    storageBucket: 'scorpions-tcc-2026.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBN1oLujn0xLKCwOL-Se2MTXd1lrAE8rpg',
    appId: '1:305720226190:android:071fed1ec304fd9212f4df',
    messagingSenderId: '305720226190',
    projectId: 'scorpions-tcc-2026',
    storageBucket: 'scorpions-tcc-2026.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAf3dbEUmzz__HcgKeYxdaBIziENZzPxyA',
    appId: '1:305720226190:ios:c61442f8d191d9ed12f4df',
    messagingSenderId: '305720226190',
    projectId: 'scorpions-tcc-2026',
    storageBucket: 'scorpions-tcc-2026.firebasestorage.app',
    iosClientId: '305720226190-p6hjaom1c73s3sl2h4qqi9juo148frp6.apps.googleusercontent.com',
    iosBundleId: 'com.scorpionslabs.scorpions',
  );
}
