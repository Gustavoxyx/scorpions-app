plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

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

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
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
