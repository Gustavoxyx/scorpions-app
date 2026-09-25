import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:scorpions/data/models/app_user.dart';
import 'package:scorpions/data/models/captured_image.dart';
import 'package:scorpions/data/models/identification.dart';
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

  @override
  void dispose() {}
}

class _RepoFalso implements IdentificationRepository {
  final List<IdentificationResult> gravacoes = <IdentificationResult>[];
  final List<String> apagados = <String>[];

  @override
  Future<void> save(IdentificationResult result) async =>
      gravacoes.add(result);

  @override
  Future<void> delete(String id) async => apagados.add(id);

  @override
  Future<List<IdentificationResult>> fetchHistory() async =>
      <IdentificationResult>[];

  @override
  Future<IdentificationResult?> findById(String id) async => null;
}

class _UploaderFalso implements ImageUploadService {
  _UploaderFalso({this.falharTudo = false});

  final bool falharTudo;
  final List<String> caminhosPedidos = <String>[];
  final List<String> apagados = <String>[];

  @override
  Future<UploadedImagePaths> uploadAll({
    required ProcessedImage image,
    required String userId,
    required String identificationId,
  }) async {
    final String prefixo = 'users/$userId/identifications/$identificationId';
    caminhosPedidos.add(prefixo);
    if (falharTudo) return const UploadedImagePaths.none();
    return UploadedImagePaths(
      original: '$prefixo/original.jpg',
      processed: '$prefixo/processed.jpg',
      thumbnail: '$prefixo/thumbnail.jpg',
    );
  }

  @override
  Future<String?> upload({
    required CapturedImage image,
    required String userId,
    required String identificationId,
  }) async =>
      null;

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
  }) {
    return IdentificationPipeline(
      auth: auth,
      repository: repo,
      processing: const DefaultImageProcessingService(),
      uploader: envio ?? uploader,
      connectivity: rede ?? const AlwaysOnlineConnectivityService(),
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
