import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// -----------------------------------------------------------------------------
// Chave de release
// -----------------------------------------------------------------------------
// Lida de `android/key.properties`, que NÃO é versionado (ver `.gitignore` e
// `android/key.properties.example`). Nenhuma senha, nenhum caminho de keystore
// e nenhum alias moram neste arquivo.
//
// O release era assinado com a chave de DEBUG. Essa chave é igual em toda
// instalação do SDK do Android, com senha pública: quem instalasse um APK
// assinado assim aceitaria "atualização" de qualquer pessoa. A Play Store
// recusa, com razão.
val keystoreProperties = Properties()
val keystoreFile = rootProject.file("key.properties")
if (keystoreFile.exists()) {
    keystoreFile.inputStream().use { keystoreProperties.load(it) }
}

val hasReleaseKey = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !keystoreProperties.getProperty(it).isNullOrBlank() }

// Saída de emergência para quem só quer medir o tamanho do APK ou testar o
// build de release num aparelho próprio, sem ter a chave. Explícita e por
// variável de ambiente, para nunca acontecer por esquecimento.
val allowDebugSigning = System.getenv("SCORPIONS_ALLOW_DEBUG_SIGNING") == "1"

android {
    namespace = "com.scorpionslabs.scorpions"

    // Fixo em 37, e não `flutter.compileSdkVersion` (que entrega 36).
    //
    // `permission_handler_android` recusa compilar contra menos que isto:
    //
    //     Dependency ':permission_handler_android' requires libraries and
    //     applications that depend on it to compile against version 37 or
    //     later of the Android APIs. :app is currently compiled against
    //     android-36.
    //
    // O AGP 9.0.1 avisa que 36 é o máximo que ele recomenda. É aviso, não
    // erro. A alternativa seria fixar uma versão antiga de
    // `permission_handler`, que é dependência em uso real — é ela que pede
    // acesso à câmera.
    //
    // `compileSdk` só diz contra quais APIs o código compila. O comportamento
    // em execução é decidido por `targetSdk`, e quais aparelhos instalam por
    // `minSdk`; os dois continuam vindo do Flutter, de propósito.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.scorpionslabs.scorpions"

        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Só arm64.
        //
        // `flutter build apk --target-platform android-arm64` filtra os
        // binários do Flutter, mas **não** os ABIs das bibliotecas nativas que
        // vêm das dependências Android. A análise do APK mostrou que sobravam:
        //
        //     lib/armeabi-v7a/libimage_processing_util_jni.so   32 KB
        //     lib/x86_64/libimage_processing_util_jni.so        59 KB
        //
        // Noventa e um quilobytes de código para arquiteturas que este APK não
        // atende. Pequeno, e é o único corte de tamanho que esta auditoria
        // encontrou: 89% do APK é o motor do Flutter, e `package:scorpions`
        // inteiro são 367 KB de 21 MB.
        //
        // ATENÇÃO ao publicar: um App Bundle (`flutter build appbundle`) precisa
        // dos três ABIs, porque é a Play Store que escolhe qual entregar a cada
        // aparelho. Este filtro é para o APK avulso — remova-o, ou condicione-o
        // à variante, antes de gerar o AAB.
        ndk {
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = when {
                hasReleaseKey -> signingConfigs.getByName("release")
                allowDebugSigning -> signingConfigs.getByName("debug")
                // Sem chave e sem a saída de emergência, o build é interrompido
                // logo abaixo, antes de produzir qualquer coisa.
                else -> null
            }
        }
    }
}

// Um release sem chave própria não é produzido em silêncio.
gradle.taskGraph.whenReady {
    val pedeRelease = allTasks.any {
        it.project == project &&
            Regex("(assemble|bundle|package|install).*Release").matches(it.name)
    }
    if (pedeRelease && !hasReleaseKey && !allowDebugSigning) {
        throw GradleException(
            """
            |
            |Build de release sem chave de assinatura.
            |
            |  Para publicar: crie `android/key.properties` a partir de
            |  `android/key.properties.example`, apontando para a sua keystore.
            |  O passo a passo está em docs/FASE0_PREPARACAO_IA.md.
            |
            |  Só para medir o APK ou testar no seu aparelho, sem publicar:
            |      SCORPIONS_ALLOW_DEBUG_SIGNING=1 flutter build apk --release
            |  O arquivo sai assinado com a chave de debug e NÃO serve para
            |  distribuição.
            |
            """.trimMargin()
        )
    }
    if (pedeRelease && !hasReleaseKey && allowDebugSigning) {
        logger.warn("AVISO: release assinado com a chave de DEBUG. Não distribua este arquivo.")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
