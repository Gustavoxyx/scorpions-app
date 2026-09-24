// =============================================================================
// Opções do projeto de demonstração — Emulator Suite.
// =============================================================================
//
// Escrito à mão e NUNCA tocado por `flutterfire configure`. Isso é deliberado:
// o arquivo existe justamente para sobreviver à regeneração do
// `firebase_options.dart`.
//
// O `projectId` começa com `demo-`, prefixo que os SDKs do Firebase e a CLI
// reconhecem como projeto puramente local: um cliente inicializado com ele
// **não alcança a nuvem**, mesmo que haja credenciais válidas na máquina e
// mesmo que alguém esqueça de chamar `useFirestoreEmulator`.
//
// Sem esta separação, `DATA_SOURCE=emulator` inicializaria o aplicativo com as
// credenciais de produção, e a salvaguarda contra escrever no banco real
// dependeria apenas de três chamadas de redirecionamento darem certo.
// =============================================================================

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Opções apontadas para o Emulator Suite.
class DemoFirebaseOptions {
  const DemoFirebaseOptions._();

  /// Identificador local. O prefixo `demo-` é o que garante o isolamento.
  static const String projectId = 'demo-scorpions';

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
    apiKey: 'demo-api-key',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: projectId,
    authDomain: 'demo-scorpions.firebaseapp.com',
    storageBucket: 'demo-scorpions.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:android:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: projectId,
    storageBucket: 'demo-scorpions.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:ios:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: projectId,
    storageBucket: 'demo-scorpions.appspot.com',
    iosBundleId: 'com.scorpionslabs.scorpions',
  );
}
