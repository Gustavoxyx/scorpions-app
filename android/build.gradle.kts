allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Destrava a compilação de release do plugin da câmera.
//
// # O sintoma
//     :camera_android_camerax:compileReleaseJavaWithJavac
//     camera-core-1.5.3-api.jar(androidx/camera/core/SurfaceRequest.class):
//     error: Cannot attach type annotations @org.jspecify.annotations.NonNull
//     to SurfaceRequest.mSurfaceRecreationCompleter:
//       class file for androidx.concurrent.futures.CallbackToFutureAdapter not found
//
// `flutter build apk --release` falhava aqui. O APK de release simplesmente
// não existia — e com ele não existia a medição de tamanho que a auditoria de
// otimização precisa, nem instalação em aparelho, nem publicação.
//
// # A causa
// `camera_android_camerax` declara `androidx.camera:camera-core:1.5.3` e nada
// mais. O campo `SurfaceRequest.mSurfaceRecreationCompleter` é um
// `CallbackToFutureAdapter.Completer`, que vive em
// `androidx.concurrent:concurrent-futures`. O POM do camera-core a traz como
// dependência de **runtime**, não de API, então ela não entra no classpath de
// compilação de quem o consome.
//
// Compilar contra a classe sem precisar dela era tolerado por versões
// anteriores do javac. A partir do JDK 21 + AGP 9, resolver a anotação de tipo
// `@NonNull` naquele campo exige carregar a classe do tipo, e a compilação
// falha. O plugin declara ter sido testado com AGP 8.13.1; este projeto usa
// 9.0.1.
//
// # Por que a correção fica aqui
// O defeito está na declaração de dependências de um pacote de terceiros, em
// `~/AppData/Local/Pub/Cache`, que é recriado a cada `pub get` — editar lá não
// sobrevive. Então a dependência que falta é acrescentada ao classpath de
// compilação daquele módulo, de fora.
//
// `compileOnly`: ela já está presente em tempo de execução, trazida pelo
// próprio camera-core. O que faltava era o javac poder lê-la. Adicionar como
// `implementation` a empacotaria duas vezes.
//
// # Quando remover
// Quando `camera_android_camerax` passar a declarar a dependência, ou quando o
// AGP voltar a tolerar a anotação. O teste é direto: comentar este bloco e
// rodar `flutter build apk --release`. Se passar, o bloco saiu de moda e pode
// sair. Enquanto não, **não remover** — já houve neste projeto uma limpeza que
// tirou uma dependência sem consumidor aparente (`cupertino_icons`) e quebrou
// o build.
// `plugins.withId`, e não direto: a configuração `compileOnly` passa a existir
// quando `com.android.library` é aplicado ao subprojeto. Declarar antes disso
// falha com "Configuration with name 'compileOnly' not found".
subprojects {
    if (project.name == "camera_android_camerax") {
        project.plugins.withId("com.android.library") {
            project.dependencies.add(
                "compileOnly",
                "androidx.concurrent:concurrent-futures:1.2.0",
            )
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
