import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/app_environment.dart';
import '../../demo_firebase_options.dart';
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

    // Qual projeto o cliente assume depende do modo do build.
    //
    // No emulador usamos `demo-scorpions`, cujo prefixo `demo-` faz os SDKs
    // recusarem qualquer chamada para a nuvem. A alternativa -- inicializar
    // sempre com as credenciais reais e confiar em `_connectEmulators()` --
    // deixaria uma falha de redirecionamento escrevendo direto em producao.
    await Firebase.initializeApp(
      options: AppEnvironmentConfig.dataSource.isEmulator
          ? DemoFirebaseOptions.currentPlatform
          : DefaultFirebaseOptions.currentPlatform,
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
        // Teto explícito, no lugar de `CACHE_SIZE_UNLIMITED`.
        //
        // Sem teto, o cache cresce enquanto houver disco — e o que ele guarda
        // é o perfil e o histórico do usuário, em claro, no aparelho. Num
        // telefone com root ou num backup do sistema, isso é extraível.
        //
        // 40 MB cobre com folga o catálogo inteiro e centenas de
        // identificações, que é o uso real. Passado isso, o Firestore
        // descarta o mais antigo sozinho — e o que foi descartado volta da
        // rede quando o usuário abrir.
        cacheSizeBytes: _cacheMaximoBytes,
      );
    }

    _initialized = true;
  }

  /// Aponta os SDKs para os emuladores locais.
  /// Teto do cache offline do Firestore. Ver a justificativa em [ensureReady].
  static const int _cacheMaximoBytes = 40 * 1024 * 1024;

  /// Descarta o cache local do Firestore.
  ///
  /// Chamado no encerramento de sessão. Sem isto, o perfil e o histórico de
  /// quem saiu continuam em disco: as Security Rules impedem o acesso **pela
  /// rede**, mas o arquivo local já está gravado, e num aparelho
  /// compartilhado ou comprometido isso é dado pessoal de uma pessoa ao
  /// alcance de outra.
  ///
  /// A ordem importa e não é negociável: `clearPersistence` recusa trabalhar
  /// enquanto houver conexão viva, então `terminate` vem antes. O SDK
  /// reconecta sozinho na próxima operação.
  ///
  /// Falhar aqui não pode impedir o logout — sair da conta é mais importante
  /// que limpar o cache, e insistir deixaria o usuário preso numa sessão que
  /// ele pediu para encerrar.
  static Future<void> clearLocalCache() async {
    try {
      await FirebaseFirestore.instance.terminate();
      await FirebaseFirestore.instance.clearPersistence();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[Scorpions] cache local não foi limpo: $error');
      }
    }
  }

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
      //
      // A guarda de `kDebugMode` não é zelo excessivo: `debugPrint` **continua
      // escrevendo em release** (só `assert` é removido), e a mensagem de uma
      // exceção do SDK carrega nome de classe interna e, às vezes, trecho de
      // URL. Em release isso iria para o logcat, legível por quem tiver o
      // aparelho na mão — exatamente o que o briefing §16/§27 proíbe.
      if (kDebugMode) {
        debugPrint('[Scorpions] App Check não ativado: $error');
      }
    }
  }
}
