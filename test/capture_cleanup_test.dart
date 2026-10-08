import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scorpions/data/models/captured_image.dart';
import 'package:scorpions/data/repositories/identification_repository.dart';
import 'package:scorpions/data/repositories/mock_auth_repository.dart';
import 'package:scorpions/data/services/capture_cleanup.dart';
import 'package:scorpions/data/services/connectivity_service.dart';
import 'package:scorpions/data/services/identification_pipeline.dart';
import 'package:scorpions/data/services/identification_service.dart';
import 'package:scorpions/data/services/image_processing_service.dart';
import 'package:scorpions/data/services/image_upload_service.dart';
import 'package:scorpions/state/identification_controller.dart';

/// Registra o que foi mandado apagar, sem tocar em disco.
class _Registro implements CaptureCleanup {
  final List<CapturedImage> descartadas = <CapturedImage>[];

  @override
  Future<void> discard(CapturedImage image) async => descartadas.add(image);
}

CapturedImage _foto(String nome, {ImageSource origem = ImageSource.camera}) =>
    CapturedImage(source: origem, capturedAt: DateTime(2026), path: nome);

void main() {
  group('FileCaptureCleanup', () {
    late Directory pasta;

    setUp(() => pasta = Directory.systemTemp.createTempSync('scorpions_'));
    tearDown(() => pasta.deleteSync(recursive: true));

    File criar(String nome) =>
        File('${pasta.path}/$nome')..writeAsBytesSync(<int>[1, 2, 3]);

    test('apaga a foto que a câmera do aplicativo gravou', () async {
      final File arquivo = criar('captura.jpg');

      await const FileCaptureCleanup().discard(_foto(arquivo.path));

      expect(arquivo.existsSync(), isFalse);
    });

    test('NÃO apaga uma imagem escolhida na galeria', () async {
      // No desktop o seletor devolve o caminho do arquivo de verdade. Apagar
      // isto seria destruir uma fotografia do usuário.
      final File arquivo = criar('foto-do-usuario.jpg');

      await const FileCaptureCleanup()
          .discard(_foto(arquivo.path, origem: ImageSource.gallery));

      expect(arquivo.existsSync(), isTrue);
    });

    test('arquivo que já sumiu não vira erro', () async {
      await expectLater(
        const FileCaptureCleanup().discard(_foto('${pasta.path}/nao-existe.jpg')),
        completes,
      );
    });

    test('imagem sem arquivo por trás é ignorada', () async {
      await expectLater(
        const FileCaptureCleanup().discard(CapturedImage.simulated()),
        completes,
      );
    });
  });

  group('o controlador descarta a foto que saiu do fluxo', () {
    late _Registro limpeza;
    late IdentificationController c;

    setUp(() {
      limpeza = _Registro();
      final MockAuthRepository auth = MockAuthRepository();
      final InMemoryIdentificationRepository repo =
          InMemoryIdentificationRepository(seedWithMockData: false);
      c = IdentificationController(
        service: MockIdentificationService(delay: Duration.zero),
        repository: repo,
        pipeline: IdentificationPipeline(
          auth: auth,
          repository: repo,
          processing: const DefaultImageProcessingService(),
          uploader: const NoopImageUploadService(),
          connectivity: const AlwaysOnlineConnectivityService(),
        ),
        demonstration: true,
        cleanup: limpeza,
      );
    });

    test('desistir da foto apaga o arquivo dela', () {
      final CapturedImage foto = _foto('a.jpg');
      c.stageImage(foto);

      c.discardPendingImage();

      expect(limpeza.descartadas, <CapturedImage>[foto]);
    });

    test('tirar outra primeira foto apaga a anterior — e a segunda junto', () {
      final CapturedImage primeira = _foto('a.jpg');
      final CapturedImage segunda = _foto('b.jpg');
      c.stageImage(primeira);
      c.beginSecondCapture();
      c.stageImage(segunda);

      c.stageImage(_foto('c.jpg'));

      expect(limpeza.descartadas, containsAll(<CapturedImage>[primeira, segunda]));
      expect(c.secondImage, isNull);
    });

    test('refazer a segunda foto apaga só a segunda', () {
      final CapturedImage primeira = _foto('a.jpg');
      final CapturedImage segunda = _foto('b.jpg');
      c.stageImage(primeira);
      c.beginSecondCapture();
      c.stageImage(segunda);

      c.discardSecondImage();

      expect(limpeza.descartadas, <CapturedImage>[segunda]);
      expect(c.pendingImage, primeira);
    });

    test('encerrar o fluxo apaga as duas', () {
      final CapturedImage primeira = _foto('a.jpg');
      final CapturedImage segunda = _foto('b.jpg');
      c.stageImage(primeira);
      c.beginSecondCapture();
      c.stageImage(segunda);

      c.reset();

      expect(limpeza.descartadas, containsAll(<CapturedImage>[primeira, segunda]));
    });

    test('encerrar o fluxo desarma a captura da segunda foto', () {
      // O defeito que a limpeza num lugar só existe para impedir: a câmera
      // ficava "aberta para a segunda" e a primeira foto da identificação
      // seguinte era anexada como segunda da anterior.
      c.stageImage(_foto('a.jpg'));
      c.beginSecondCapture();

      c.reset();
      final CapturedImage nova = _foto('b.jpg');
      c.stageImage(nova);

      expect(c.isCapturingSecond, isFalse);
      expect(c.pendingImage, nova);
      expect(c.secondImage, isNull);
    });
  });
}
