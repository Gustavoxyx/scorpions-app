import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:scorpions/data/models/app_user.dart';
import 'package:scorpions/data/models/captured_image.dart';
import 'package:scorpions/data/models/capture_instruction.dart';
import 'package:scorpions/data/models/identification.dart';
import 'package:scorpions/data/models/secondary_view.dart';
import 'package:scorpions/data/models/identification_status.dart';
import 'package:scorpions/data/models/image_validation.dart';
import 'package:scorpions/data/models/processed_image.dart';
import 'package:scorpions/data/repositories/auth_repository.dart';
import 'package:scorpions/data/repositories/identification_repository.dart';
import 'package:scorpions/data/services/connectivity_service.dart';
import 'package:scorpions/data/services/failure.dart';
import 'package:scorpions/data/services/identification_pipeline.dart';
import 'package:scorpions/data/services/image_processing_service.dart';
import 'package:scorpions/data/services/image_upload_service.dart';

// ---------------------------------------------------------------------------
// Dublês
// ---------------------------------------------------------------------------

/// Sessão controlada. O ponto do teste é que o pipeline leia o dono **daqui**,
/// e não de um parâmetro — não existe assinatura que aceite um `userId`.
class _AuthFalso implements AuthRepository {
  _AuthFalso(this._user);

  AppUser? _user;

  @override
  AppUser? get currentUser => _user;

  void sair() => _user = null;

  @override
  Stream<AppUser?> authStateChanges() => Stream<AppUser?>.value(_user);

  @override
  Future<AppUser> signIn({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> sendPasswordReset(String email) => throw UnimplementedError();

  @override
  Future<void> signOut() async => _user = null;

  // O pipeline de identificação não usa nenhum destes. Lançar em vez de
  // devolver um valor plausível é deliberado: se um dia ele passar a chamá-los,
  // o teste quebra e diz onde — em vez de passar silenciosamente sobre um dublê
  // que inventou uma resposta.
  @override
  Future<void> sendEmailVerification() => throw UnimplementedError();

  /// O que a recarga devolve. Nulo simula a recarga falhando.
  AppUser? aposRecarga;

  @override
  Future<AppUser?> reload() async {
    final AppUser? novo = aposRecarga;
    if (novo == null) throw UnimplementedError();
    return _user = novo;
  }

  @override
  Future<void> reauthenticate(String password) => throw UnimplementedError();

  @override
  Future<String?> idToken({bool forceRefresh = false}) =>
      throw UnimplementedError();

  @override
  void dispose() {}
}

class _RepoFalso implements IdentificationRepository {
  final List<IdentificationResult> gravacoes = <IdentificationResult>[];
  final List<String> apagados = <String>[];

  @override
  Future<void> save(IdentificationResult result) async =>
      gravacoes.add(result);

  /// Registra as ligações de imagem como uma gravação a mais, para que os
  /// testes continuem lendo a história completa em `gravacoes`.
  @override
  Future<void> attachUploadResult(
    String id, {
    String? imageUrl,
    String? thumbnailUrl,
    String? errorCode,
    SecondaryView? secondaryView,
  }) async {
    final int i = gravacoes.indexWhere((IdentificationResult r) => r.id == id);
    if (i < 0) return;
    gravacoes.add(gravacoes[i].copyWith(
      imageUrl: imageUrl,
      thumbnailUrl: thumbnailUrl,
      errorCode: errorCode,
      secondaryView: secondaryView,
    ));
  }

  @override
  Future<void> delete(String id) async => apagados.add(id);

  @override
  Future<List<IdentificationResult>> fetchHistory() async =>
      <IdentificationResult>[];

  @override
  Future<IdentificationResult?> findById(String id) async => null;
}

class _UploaderFalso implements ImageUploadService {
  _UploaderFalso({this.falharTudo = false, this.lancar});

  final bool falharTudo;

  /// Exceção a lançar em vez de responder.
  ///
  /// `falharTudo` cobre o envio que **responde** sem ter enviado nada; este
  /// cobre o envio que nem chega a responder — que é o que o Cloud Storage
  /// faz quando o projeto está no plano Spark. São falhas diferentes e
  /// percorrem caminhos diferentes do pipeline.
  final Object? lancar;

  final List<String> caminhosPedidos = <String>[];
  final List<String> apagados = <String>[];

  /// Qual vista cada pedido de envio trouxe, na ordem em que chegaram.
  final List<int> vistasPedidas = <int>[];

  /// Quantos envios estavam em andamento ao mesmo tempo, no pico.
  ///
  /// É como o teste de paralelismo distingue "as duas subiram juntas" de "uma
  /// esperou a outra": com envio sequencial, este número nunca passa de 1.
  int picoSimultaneo = 0;
  int _emAndamento = 0;

  /// Faz a segunda vista falhar, deixando a primeira passar.
  bool falharSegundaVista = false;

  @override
  Future<UploadedImagePaths> uploadAll({
    required ProcessedImage image,
    required String userId,
    required String identificationId,
    int viewIndex = 1,
  }) async {
    final String prefixo = 'users/$userId/identifications/$identificationId';
    caminhosPedidos.add(prefixo);
    vistasPedidas.add(viewIndex);

    _emAndamento++;
    if (_emAndamento > picoSimultaneo) picoSimultaneo = _emAndamento;
    // Cede a vez: sem isto os dois "envios" terminariam um depois do outro no
    // mesmo turno do laço de eventos, e o pico seria 1 mesmo em paralelo.
    await Future<void>.delayed(Duration.zero);
    _emAndamento--;

    if (lancar != null) throw lancar!;
    if (falharTudo) return const UploadedImagePaths.none();
    if (viewIndex == 2 && falharSegundaVista) {
      return const UploadedImagePaths.none();
    }

    final String sufixo = viewIndex == 2 ? '-2' : '';
    return UploadedImagePaths(
      original: '$prefixo/original$sufixo.jpg',
      processed: '$prefixo/processed$sufixo.jpg',
      thumbnail: '$prefixo/thumbnail$sufixo.jpg',
    );
  }

  @override
  Future<void> deleteFor({
    required String userId,
    required String identificationId,
  }) async =>
      apagados.add(identificationId);
}

class _SemRede implements ConnectivityService {
  @override
  Future<bool> hasConnection() async => false;
}

// ---------------------------------------------------------------------------

Uint8List _foto({int largura = 1200, int altura = 900}) {
  final img.Image im = img.Image(width: largura, height: altura);
  final Random r = Random(4);
  for (int y = 0; y < altura; y++) {
    for (int x = 0; x < largura; x++) {
      final double onda = 0.5 + 0.35 * sin(x / 50) * cos(y / 60);
      final int v = ((onda + r.nextDouble() * 0.2) * 205).clamp(0, 255).round();
      im.setPixelRgb(x, y, v, (v * 0.85).round(), (v * 0.6).round());
    }
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 90));
}

CapturedImage _imagem(Uint8List bytes) => CapturedImage(
      source: ImageSource.camera,
      capturedAt: DateTime(2026, 9, 25),
      bytes: bytes,
    );

void main() {
  late _AuthFalso auth;
  late _RepoFalso repo;
  late _UploaderFalso uploader;

  IdentificationPipeline montar({
    ConnectivityService? rede,
    ImageUploadService? envio,
    bool exigeEmail = false,
  }) {
    return IdentificationPipeline(
      auth: auth,
      repository: repo,
      processing: const DefaultImageProcessingService(),
      uploader: envio ?? uploader,
      connectivity: rede ?? const AlwaysOnlineConnectivityService(),
      requireVerifiedEmail: exigeEmail,
    );
  }

  setUp(() {
    auth = _AuthFalso(const AppUser(
      id: 'uid-do-dono',
      name: 'Gustavo',
      email: 'g@exemplo.com',
    ));
    repo = _RepoFalso();
    uploader = _UploaderFalso();
  });

  group('prepare', () {
    test('aceita uma foto boa e devolve as três formas', () async {
      final ImagePreparation p = await montar().prepare(_imagem(_foto()));
      expect(p.isValid, isTrue);
      expect(p.canProceed, isTrue);
      expect(p.image!.thumbnail.width, lessThanOrEqualTo(320));
    });

    test('recusa sem lançar — a tela precisa exibir o motivo', () async {
      final ImagePreparation p =
          await montar().prepare(_imagem(_foto(largura: 300, altura: 220)));
      expect(p.isValid, isFalse);
      expect(p.validation.code, ImageValidationCode.tooFewPixels);
      expect(p.validation.message, isNotEmpty);
    });
  });

  group('e-mail confirmado', () {
    test('sem confirmação, recusa antes de criar qualquer coisa', () async {
      final IdentificationPipeline p = montar(exigeEmail: true);
      final CapturedImage imagem = _imagem(_foto());
      final ImagePreparation prep = await p.prepare(imagem);

      await expectLater(
        p.submit(image: imagem, preparation: prep),
        throwsA(isA<AppFailure>()
            .having((AppFailure f) => f.code, 'code', 'email-not-verified')),
      );
      expect(repo.gravacoes, isEmpty,
          reason: 'um registro criado aqui seria recusado pelas regras e '
              'ficaria só na memória do aparelho');
    });

    test('quem acabou de confirmar no navegador não é barrado', () async {
      // O usuário em memória ainda diz "não confirmado"; a recarga traz a
      // verdade. Recusar aqui seria errar no pior momento.
      auth.aposRecarga = const AppUser(
        id: 'uid-do-dono',
        name: 'Gustavo',
        email: 'g@exemplo.com',
        emailVerified: true,
      );
      final IdentificationPipeline p = montar(exigeEmail: true);
      final CapturedImage imagem = _imagem(_foto());
      final ImagePreparation prep = await p.prepare(imagem);

      final PipelineOutcome saida =
          await p.submit(image: imagem, preparation: prep);
      expect(saida.cancelled, isFalse);
      expect(repo.gravacoes, isNotEmpty);
    });

    test('no modo simulado a exigência não existe', () async {
      final IdentificationPipeline p = montar();
      final CapturedImage imagem = _imagem(_foto());
      final ImagePreparation prep = await p.prepare(imagem);

      final PipelineOutcome saida =
          await p.submit(image: imagem, preparation: prep);
      expect(saida.cancelled, isFalse);
    });
  });

  group('submit', () {
    test('grava em processing e depois com os caminhos', () async {
      final IdentificationPipeline p = montar();
      final CapturedImage imagem = _imagem(_foto());
      final ImagePreparation prep = await p.prepare(imagem);

      final List<PipelineStage> etapas = <PipelineStage>[];
      final PipelineOutcome saida = await p.submit(
        image: imagem,
        preparation: prep,
        onStage: etapas.add,
      );

      expect(saida.cancelled, isFalse);
      expect(saida.result!.status, IdentificationStatus.processing,
          reason: 'sem modelo, processing é o estado honesto');
      expect(etapas, containsAllInOrder(<PipelineStage>[
        PipelineStage.registering,
        PipelineStage.uploading,
        PipelineStage.awaitingAnalysis,
      ]));

      expect(repo.gravacoes.length, 2);
      expect(repo.gravacoes.first.imageUrl, isNull,
          reason: 'o registro nasce antes do envio, para não se perder');
      expect(repo.gravacoes.last.imageUrl, endsWith('processed.jpg'));
      expect(repo.gravacoes.last.thumbnailUrl, endsWith('thumbnail.jpg'));
    });

    test('as medidas de qualidade são gravadas junto', () async {
      final IdentificationPipeline p = montar();
      final CapturedImage imagem = _imagem(_foto());
      await p.submit(image: imagem, preparation: await p.prepare(imagem));

      final Map<String, Object?> q = repo.gravacoes.first.imageQuality!;
      expect(q['quality'], isA<String>());
      expect(q['sharpness'], isA<double>());
    });

    test('o dono vem da sessão, e o caminho é montado a partir dele', () async {
      final IdentificationPipeline p = montar();
      final CapturedImage imagem = _imagem(_foto());
      await p.submit(image: imagem, preparation: await p.prepare(imagem));

      expect(uploader.caminhosPedidos.single,
          startsWith('users/uid-do-dono/identifications/'));
      expect(repo.gravacoes.first.userId, 'uid-do-dono');
    });

    test('sem sessão, recusa antes de tocar em qualquer coisa', () async {
      final IdentificationPipeline p = montar();
      final CapturedImage imagem = _imagem(_foto());
      final ImagePreparation prep = await p.prepare(imagem);
      auth.sair();

      await expectLater(
        p.submit(image: imagem, preparation: prep),
        throwsA(isA<AppFailure>().having(
            (AppFailure f) => f.kind, 'kind', FailureKind.authentication)),
      );
      expect(repo.gravacoes, isEmpty);
    });

    test('offline recusa sem gravar nada', () async {
      final IdentificationPipeline p = montar(rede: _SemRede());
      final CapturedImage imagem = _imagem(_foto());
      final ImagePreparation prep = await p.prepare(imagem);

      await expectLater(
        p.submit(image: imagem, preparation: prep),
        throwsA(isA<AppFailure>()
            .having((AppFailure f) => f.kind, 'kind', FailureKind.network)),
      );
      expect(repo.gravacoes, isEmpty);
      expect(uploader.caminhosPedidos, isEmpty);
    });

    test('upload que falha inteiro não derruba o registro', () async {
      final IdentificationPipeline p =
          montar(envio: _UploaderFalso(falharTudo: true));
      final CapturedImage imagem = _imagem(_foto());
      final PipelineOutcome saida = await p.submit(
        image: imagem,
        preparation: await p.prepare(imagem),
      );

      expect(saida.result, isNotNull,
          reason: 'a identificação vale mais que o anexo');
      expect(saida.result!.imageUrl, isNull);
      expect(repo.gravacoes.last.status, IdentificationStatus.processing);
    });

    // Regressão da Fase 4.
    //
    // Quando o envio saiu do repositório e veio para o pipeline, a tolerância
    // a falha ficou para trás: `uploadAll` passou a ser chamado sem `catch`.
    // O documento já estava gravado uma linha antes, então a exceção deixava
    // um registro preso em `processing` que ninguém mais tocava — e o usuário
    // via um erro depois de a foto já ter sido aceita.
    //
    // É o caminho que o projeto percorre HOJE: Storage exige Blaze, que ainda
    // não foi autorizado, então toda tentativa real cai aqui.
    test('upload que lança não perde a identificação nem a marca', () async {
      final IdentificationPipeline p = montar(
        envio: _UploaderFalso(
          lancar: const AppFailure(
            kind: FailureKind.permission,
            message: 'Armazenamento indisponível.',
            code: 'storage-unavailable',
          ),
        ),
      );
      final CapturedImage imagem = _imagem(_foto());

      final PipelineOutcome saida = await p.submit(
        image: imagem,
        preparation: await p.prepare(imagem),
      );

      expect(saida.result, isNotNull,
          reason: 'a exceção do envio não pode derrubar o que já foi gravado');
      expect(saida.result!.imageUrl, isNull);
      expect(saida.result!.errorCode, 'storage-unavailable',
          reason: 'sem a marca, a tela não tem como explicar a foto ausente');
      expect(repo.gravacoes.last.errorCode, 'storage-unavailable',
          reason: 'a marca precisa chegar ao documento, não só ao retorno');
      expect(repo.apagados, isEmpty,
          reason: 'falha de envio não é cancelamento — nada a apagar');
    });

    test('exceção desconhecida no envio vira código genérico', () async {
      final IdentificationPipeline p =
          montar(envio: _UploaderFalso(lancar: StateError('qualquer coisa')));
      final CapturedImage imagem = _imagem(_foto());

      final PipelineOutcome saida = await p.submit(
        image: imagem,
        preparation: await p.prepare(imagem),
      );

      expect(saida.result!.errorCode, 'upload-failed');
      expect(repo.apagados, isEmpty);
    });
  });

  group('duas vistas (Fase 5)', () {
    /// A segunda captura, pronta para envio, com a instrução da cauda.
    Future<SecondaryCapture> segundaDe(
      IdentificationPipeline p, {
      ImageCaptureInstruction instrucao = ImageCaptureInstruction.tail,
    }) async {
      final CapturedImage imagem = _imagem(_foto());
      return SecondaryCapture(
        image: imagem,
        preparation: await p.prepare(imagem),
        instruction: instrucao,
      );
    }

    test('sem segunda foto, o registro é o de sempre', () async {
      // A garantia de compatibilidade: uma identificação de uma foto só não
      // muda em nada por o pipeline saber lidar com duas.
      final IdentificationPipeline p = montar();
      final CapturedImage imagem = _imagem(_foto());

      final PipelineOutcome saida =
          await p.submit(image: imagem, preparation: await p.prepare(imagem));

      expect(saida.result!.viewCount, 1);
      expect(saida.result!.secondaryView, isNull);
      expect(uploader.vistasPedidas, <int>[1]);
    });

    test('a segunda vista é registrada com o que foi PEDIDO', () async {
      // Guardar o pedido junto do resultado é o que permite, depois, perguntar
      // "o usuário fotografou a cauda quando pedimos a cauda?".
      final IdentificationPipeline p = montar();
      final CapturedImage imagem = _imagem(_foto());

      final PipelineOutcome saida = await p.submit(
        image: imagem,
        preparation: await p.prepare(imagem),
        secondary: await segundaDe(p),
      );

      final SecondaryView segunda = saida.result!.secondaryView!;
      expect(saida.result!.viewCount, 2);
      expect(segunda.captureType, CaptureType.tail);
      expect(segunda.instructionId, ImageCaptureInstruction.tail.id);
      expect(segunda.imageQuality, isNotNull,
          reason: 'as medidas da segunda foto também são gravadas');
    });

    test('a segunda vista já existe no registro ANTES do envio', () async {
      // Igual à primeira: o registro nasce antes de qualquer arquivo subir,
      // para que uma falha de rede não leve junto a informação de que houve
      // uma segunda foto.
      final IdentificationPipeline p = montar();
      final CapturedImage imagem = _imagem(_foto());

      await p.submit(
        image: imagem,
        preparation: await p.prepare(imagem),
        secondary: await segundaDe(p),
      );

      final IdentificationResult criado = repo.gravacoes.first;
      expect(criado.secondaryView, isNotNull);
      expect(criado.secondaryView!.imageUrl, isNull);
      expect(criado.secondaryView!.captureType, CaptureType.tail);
    });

    test('os arquivos da segunda vista levam sufixo, na mesma pasta', () async {
      final IdentificationPipeline p = montar();
      final CapturedImage imagem = _imagem(_foto());

      final PipelineOutcome saida = await p.submit(
        image: imagem,
        preparation: await p.prepare(imagem),
        secondary: await segundaDe(p),
      );

      final IdentificationResult r = saida.result!;
      expect(r.imageUrl, endsWith('/processed.jpg'));
      expect(r.secondaryView!.imageUrl, endsWith('/processed-2.jpg'));
      expect(r.secondaryView!.thumbnailUrl, endsWith('/thumbnail-2.jpg'));

      // Mesma pasta: apagar a identificação apaga as duas com um prefixo só.
      String pasta(String caminho) =>
          caminho.substring(0, caminho.lastIndexOf('/'));
      expect(pasta(r.secondaryView!.imageUrl!), pasta(r.imageUrl!));
    });

    test('as duas vistas sobem EM PARALELO', () async {
      // O briefing de otimização (§27) pede isto por nome. Com envio
      // sequencial, o pico de envios simultâneos nunca passaria de 1.
      final IdentificationPipeline p = montar();
      final CapturedImage imagem = _imagem(_foto());

      await p.submit(
        image: imagem,
        preparation: await p.prepare(imagem),
        secondary: await segundaDe(p),
      );

      expect(uploader.vistasPedidas, unorderedEquals(<int>[1, 2]));
      expect(
        uploader.picoSimultaneo,
        2,
        reason: 'uma vista esperou a outra terminar para começar',
      );
    });

    test('a segunda falha, a primeira sobrevive', () async {
      // Uma vista ruim não invalida a identificação se a outra tiver
      // informação suficiente (§5). Uma vista que não subiu segue a mesma
      // lógica.
      final IdentificationPipeline p = montar();
      uploader.falharSegundaVista = true;
      final CapturedImage imagem = _imagem(_foto());

      final PipelineOutcome saida = await p.submit(
        image: imagem,
        preparation: await p.prepare(imagem),
        secondary: await segundaDe(p),
      );

      final IdentificationResult r = saida.result!;
      expect(r.imageUrl, endsWith('/processed.jpg'),
          reason: 'a primeira foto subiu e precisa estar referenciada');
      expect(r.secondaryView!.imageUrl, isNull);
      // A segunda vista continua registrada: sabe-se que foi tirada e qual
      // era, só não se tem o arquivo.
      expect(r.secondaryView!.captureType, CaptureType.tail);
      expect(repo.apagados, isEmpty, reason: 'nada é apagado por isso');
    });

    test('exceção no envio de uma vista não derruba a outra', () async {
      // `Future.wait` propaga a primeira exceção e abandona o resto. O que
      // impede isso aqui é cada envio capturar o próprio erro — e é o que este
      // teste trava.
      final _UploaderFalso quebrado = _UploaderFalso(lancar: StateError('x'));
      final IdentificationPipeline p = montar(envio: quebrado);
      final CapturedImage imagem = _imagem(_foto());

      final PipelineOutcome saida = await p.submit(
        image: imagem,
        preparation: await p.prepare(imagem),
        secondary: await segundaDe(p),
      );

      expect(saida.cancelled, isFalse);
      expect(saida.result!.errorCode, 'upload-failed');
      expect(saida.result!.viewCount, 2);
      expect(quebrado.vistasPedidas, unorderedEquals(<int>[1, 2]),
          reason: 'as duas foram tentadas, mesmo com a primeira lançando');
    });

    test('o que o cliente grava NÃO contém conclusão de análise', () async {
      // A segunda vista é do cliente; o que as duas fotos disseram juntas não
      // é. `fusion` é campo de servidor (auditoria HIGH-1), e este teste
      // garante que ele não escapa para o mapa de criação por distração.
      final IdentificationPipeline p = montar();
      final CapturedImage imagem = _imagem(_foto());

      final PipelineOutcome saida = await p.submit(
        image: imagem,
        preparation: await p.prepare(imagem),
        secondary: await segundaDe(p),
      );

      final Map<String, Object?> doCliente =
          saida.result!.toClientCreateMap();

      expect(doCliente['viewCount'], 2);
      expect(doCliente['secondaryView'], isA<Map<String, Object?>>());
      for (final String proibido in <String>[
        'fusion',
        'confidence',
        'speciesId',
        'species',
        'modelVersion',
      ]) {
        expect(doCliente.containsKey(proibido), isFalse,
            reason: '"$proibido" é campo de servidor');
      }

      final Map<String, Object?> vista =
          doCliente['secondaryView']! as Map<String, Object?>;
      expect(
        vista.keys.toSet(),
        <String>{
          'captureType',
          'instructionId',
          'imageUrl',
          'thumbnailUrl',
          'imageQuality',
        },
        reason: 'são exatamente as chaves que a Security Rules aceita',
      );
    });

    test('cancelar com duas vistas apaga a identificação inteira', () async {
      final IdentificationPipeline p = montar();
      final CapturedImage imagem = _imagem(_foto());
      final ImagePreparation prep = await p.prepare(imagem);
      final SecondaryCapture segunda = await segundaDe(p);

      final PipelineOutcome saida = await p.submit(
        image: imagem,
        preparation: prep,
        secondary: segunda,
        onStage: (PipelineStage s) {
          if (s == PipelineStage.uploading) p.cancel();
        },
      );

      expect(saida.cancelled, isTrue);
      // Um `deleteFor` só, pelo id: ele cobre as duas vistas porque elas
      // moram na mesma pasta.
      expect(uploader.apagados, hasLength(1));
      expect(repo.apagados, hasLength(1));
    });

    test('registro de duas vistas sobrevive a ida e volta pelo banco', () {
      // O histórico lê o documento de volta. Se `fromMap` perdesse a segunda
      // vista, a tela de resultado mostraria uma foto onde houve duas.
      final Map<String, dynamic> documento = <String, dynamic>{
        'userId': 'uid-do-dono',
        'status': 'processing',
        'imageUrl': 'users/u/identifications/i/processed.jpg',
        'viewCount': 2,
        'secondaryView': <String, dynamic>{
          'captureType': 'tail',
          'instructionId': 'secondary-tail',
          'imageUrl': 'users/u/identifications/i/processed-2.jpg',
          'thumbnailUrl': 'users/u/identifications/i/thumbnail-2.jpg',
          'imageQuality': <String, dynamic>{'quality': 'good'},
        },
      };

      final IdentificationResult lido =
          IdentificationResult.fromMap('i', documento);

      expect(lido.viewCount, 2);
      expect(lido.secondaryView!.captureType, CaptureType.tail);
      expect(lido.secondaryView!.imageUrl, endsWith('processed-2.jpg'));
      expect(lido.secondaryView!.imageQuality!['quality'], 'good');
    });

    test('documento antigo, sem os campos novos, é lido como uma foto', () {
      // Nenhuma migração: todo registro anterior continua válido.
      final IdentificationResult lido = IdentificationResult.fromMap(
        'antigo',
        <String, dynamic>{'userId': 'u', 'status': 'processing'},
      );

      expect(lido.viewCount, 1);
      expect(lido.secondaryView, isNull);
      expect(lido.multiView, isNull);
    });
  });

  group('cancelamento (§18)', () {
    test('cancelar antes do registro não deixa rastro', () async {
      final IdentificationPipeline p = montar();
      final CapturedImage imagem = _imagem(_foto());
      final ImagePreparation prep = await p.prepare(imagem);

      p.cancel();
      final PipelineOutcome saida =
          await p.submit(image: imagem, preparation: prep);

      expect(saida.cancelled, isTrue);
      expect(saida.result, isNull);
      expect(repo.gravacoes, isEmpty);
      expect(repo.apagados, isEmpty);
    });

    test('cancelar depois do registro apaga documento e arquivos', () async {
      final IdentificationPipeline p = montar();
      final CapturedImage imagem = _imagem(_foto());
      final ImagePreparation prep = await p.prepare(imagem);

      final PipelineOutcome saida = await p.submit(
        image: imagem,
        preparation: prep,
        onStage: (PipelineStage s) {
          // Cancela quando o envio começa — nesse ponto o documento já
          // existe, que é justamente o caso em que pode sobrar órfão.
          //
          // Cancelar antes, em `registering`, cai no outro caminho: o
          // pipeline desiste sem chegar a gravar, e não há o que limpar.
          if (s == PipelineStage.uploading) p.cancel();
        },
      );

      expect(saida.cancelled, isTrue);
      expect(repo.gravacoes.length, 1, reason: 'o registro chegou a existir');
      expect(repo.apagados.single, repo.gravacoes.single.id,
          reason: 'e foi removido — órfão no banco é pior que nada');
      expect(uploader.apagados.single, repo.gravacoes.single.id);
    });
  });

  test('cada identificação recebe um id distinto e ordenável', () async {
    final IdentificationPipeline p = montar();
    final CapturedImage imagem = _imagem(_foto());
    final ImagePreparation prep = await p.prepare(imagem);

    await p.submit(image: imagem, preparation: prep);
    await p.submit(image: imagem, preparation: prep);

    final List<String> ids = repo.gravacoes
        .map((IdentificationResult r) => r.id)
        .toSet()
        .toList();
    expect(ids.length, 2);
    expect(ids.first.compareTo(ids.last) < 0, isTrue,
        reason: 'ids em ordem de criação mantêm o índice compacto');
  });

  group('geração de id', () {
    test('milhares seguidos, nenhum repetido', () {
      // A versão anterior usava microssegundos e colidia: no Windows o
      // relógio tem resolução de milissegundo, então duas chamadas no mesmo
      // milissegundo produziam o mesmo id — e um documento sobrescrevia o
      // outro em silêncio.
      final Set<String> vistos = <String>{};
      for (int i = 0; i < 5000; i++) {
        expect(vistos.add(IdentificationPipeline.newId()), isTrue,
            reason: 'colisão na iteração $i');
      }
    });

    test('o prefixo de tempo mantém a ordem de criação', () async {
      final String antes = IdentificationPipeline.newId();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final String depois = IdentificationPipeline.newId();
      expect(antes.substring(0, 8).compareTo(depois.substring(0, 8)),
          lessThan(0));
    });
  });
}
