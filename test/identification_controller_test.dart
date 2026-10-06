import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:scorpions/data/mock/mock_species.dart';
import 'package:scorpions/data/models/app_user.dart';
import 'package:scorpions/data/models/capture_instruction.dart';
import 'package:scorpions/data/models/captured_image.dart';
import 'package:scorpions/data/models/identification.dart';
import 'package:scorpions/data/models/identification_status.dart';
import 'package:scorpions/data/models/image_quality.dart';
import 'package:scorpions/data/repositories/auth_repository.dart';
import 'package:scorpions/data/repositories/identification_repository.dart';
import 'package:scorpions/data/services/capture_plan_service.dart';
import 'package:scorpions/data/services/connectivity_service.dart';
import 'package:scorpions/data/services/demo_multi_view_service.dart';
import 'package:scorpions/data/services/identification_pipeline.dart';
import 'package:scorpions/data/services/identification_service.dart';
import 'package:scorpions/data/services/image_processing_service.dart';
import 'package:scorpions/data/services/image_upload_service.dart';
import 'package:scorpions/data/services/multi_view_fusion_service.dart';
import 'package:scorpions/state/identification_controller.dart';

/// Testes do fluxo de identificação visto pelo controlador.
///
/// O pipeline tem os próprios testes, e a fusão também. Aqui o que está sob
/// teste é a **sequência que a tela percorre**: primeira foto, a oferta da
/// segunda, a captura dela, e o envio das duas — e o que acontece quando a
/// pessoa muda de ideia no meio.
///
/// É onde o estado pode ficar inconsistente: uma segunda foto sobrevivendo a
/// uma primeira nova, a câmera achando que ainda está na segunda vista, uma
/// instrução recalculada depois de a foto já ter sido tirada.
void main() {
  late InMemoryIdentificationRepository repo;

  IdentificationController montar({
    bool demonstration = true,
    double disagreement = 0.0,
    IdentificationService? servico,
    CapturePlanService plano = const HeuristicCapturePlanService(),
  }) {
    final _Auth auth = _Auth();
    return IdentificationController(
      service: servico ?? _ServicoFixo(),
      repository: repo,
      pipeline: IdentificationPipeline(
        auth: auth,
        repository: repo,
        processing: const DefaultImageProcessingService(),
        uploader: const NoopImageUploadService(),
        connectivity: const AlwaysOnlineConnectivityService(),
      ),
      demonstration: demonstration,
      plan: plano,
      demoFusion: DemoMultiViewService(
        random: Random(7),
        disagreementRate: disagreement,
      ),
    );
  }

  /// Percorre o caminho inteiro de duas fotos, como a tela faria.
  Future<void> duasFotos(IdentificationController c) async {
    final CapturedImage primeira = CapturedImage.simulated();
    c.stageImage(primeira);
    await c.inspect(primeira);

    c.beginSecondCapture();
    c.stageImage(CapturedImage.simulated());
    await c.inspectSecond();

    await c.submit(primeira);
  }

  setUp(() {
    repo = InMemoryIdentificationRepository(seedWithMockData: false);
  });

  // ===========================================================================
  // O defeito do histórico duplicado
  // ===========================================================================

  group('modo de demonstração', () {
    test('uma identificação deixa UM registro no histórico, não dois', () async {
      // Isto era um defeito, e existia antes das duas fotos.
      //
      // O pipeline grava o registro com um id; o motor simulado devolvia o
      // desfecho com outro (`mock-…`); e os dois eram salvos. Cada
      // identificação deixava no histórico o resultado **e** um registro
      // original preso em "processando" para sempre.
      final IdentificationController c = montar();
      final CapturedImage foto = CapturedImage.simulated();
      c.stageImage(foto);
      await c.inspect(foto);
      await c.submit(foto);

      final List<IdentificationResult> historico = await repo.fetchHistory();

      expect(historico, hasLength(1));
      expect(historico.single.status, isNot(IdentificationStatus.processing),
          reason: 'o registro em processamento precisa ter sido substituído');
      expect(c.lastResult!.id, historico.single.id);
    });

    test('várias identificações seguidas não acumulam órfãos', () async {
      final IdentificationController c = montar();

      for (int i = 0; i < 4; i++) {
        final CapturedImage foto = CapturedImage.simulated();
        c.stageImage(foto);
        await c.inspect(foto);
        await c.submit(foto);
      }

      final List<IdentificationResult> historico = await repo.fetchHistory();
      expect(historico, hasLength(4));
      expect(
        historico.where((IdentificationResult r) =>
            r.status == IdentificationStatus.processing),
        isEmpty,
      );
    });
  });

  // ===========================================================================
  // A sequência de duas fotos
  // ===========================================================================

  group('duas fotografias', () {
    test('a câmera começa pedindo a primeira vista', () {
      final IdentificationController c = montar();

      expect(c.isCapturingSecond, isFalse);
      expect(c.currentInstruction.captureType, CaptureType.topView);
      expect(c.hasSecondView, isFalse);
    });

    test('depois da primeira, a instrução em vigor passa a ser a da segunda',
        () async {
      final IdentificationController c = montar();
      final CapturedImage primeira = CapturedImage.simulated();
      c.stageImage(primeira);
      await c.inspect(primeira);

      c.beginSecondCapture();

      expect(c.isCapturingSecond, isTrue);
      expect(c.currentInstruction, c.secondInstruction);
      expect(c.currentInstruction.captureType, isNot(CaptureType.topView));
    });

    test('a foto que chega durante a segunda captura NÃO substitui a primeira',
        () async {
      // O erro que este fluxo mais convida a cometer: tratar toda foto nova
      // como "a foto pendente".
      final IdentificationController c = montar();
      final CapturedImage primeira = CapturedImage.simulated();
      c.stageImage(primeira);
      await c.inspect(primeira);

      c.beginSecondCapture();
      final CapturedImage segunda = CapturedImage.simulated();
      c.stageImage(segunda);

      expect(c.pendingImage, same(primeira));
      expect(c.secondImage, same(segunda));
      expect(c.preparation, isNotNull,
          reason: 'a inspeção da primeira não pode ser perdida');
      expect(c.isCapturingSecond, isFalse,
          reason: 'a captura terminou: a próxima foto não é mais a segunda');
    });

    test('a segunda só conta depois de inspecionada', () async {
      final IdentificationController c = montar();
      final CapturedImage primeira = CapturedImage.simulated();
      c.stageImage(primeira);
      await c.inspect(primeira);
      c.beginSecondCapture();
      c.stageImage(CapturedImage.simulated());

      expect(c.hasSecondView, isFalse);

      await c.inspectSecond();

      expect(c.hasSecondView, isTrue);
    });

    test('uma PRIMEIRA foto nova descarta a segunda', () async {
      // A segunda foi pedida com base no que se mediu da primeira. Trocada a
      // primeira, a segunda deixa de ser a resposta a pergunta nenhuma.
      final IdentificationController c = montar();
      await duasFotos(c);
      c.reset();

      final CapturedImage a = CapturedImage.simulated();
      c.stageImage(a);
      await c.inspect(a);
      c.beginSecondCapture();
      c.stageImage(CapturedImage.simulated());
      await c.inspectSecond();
      expect(c.hasSecondView, isTrue);

      c.stageImage(CapturedImage.simulated()); // nova primeira

      expect(c.secondImage, isNull);
      expect(c.hasSecondView, isFalse);
    });

    test('desistir da segunda captura mantém a primeira', () async {
      // O animal fugiu, a pessoa preferiu não chegar perto. A identificação de
      // uma foto só continua válida.
      final IdentificationController c = montar();
      final CapturedImage primeira = CapturedImage.simulated();
      c.stageImage(primeira);
      await c.inspect(primeira);

      c.beginSecondCapture();
      c.cancelSecondCapture();

      expect(c.isCapturingSecond, isFalse);
      expect(c.pendingImage, same(primeira));
      expect(c.preparation, isNotNull);
    });

    test('descartar a segunda foto permite refazê-la ou seguir sem ela',
        () async {
      final IdentificationController c = montar();
      final CapturedImage primeira = CapturedImage.simulated();
      c.stageImage(primeira);
      await c.inspect(primeira);
      c.beginSecondCapture();
      c.stageImage(CapturedImage.simulated());
      await c.inspectSecond();

      c.discardSecondImage();

      expect(c.secondImage, isNull);
      expect(c.hasSecondView, isFalse);
      expect(c.pendingImage, same(primeira));
    });

    test('a instrução fica fixada no momento em que a captura abre', () async {
      // A instrução gravada no registro precisa ser a que a pessoa VIU ao
      // fotografar. Se fosse recalculada depois, um plano que mudasse de ideia
      // registraria "pedimos o perfil" numa foto tirada sob "aproxime a cauda".
      final _PlanoQueMuda plano = _PlanoQueMuda();
      final IdentificationController c = montar(plano: plano);
      final CapturedImage primeira = CapturedImage.simulated();
      c.stageImage(primeira);
      await c.inspect(primeira);

      c.beginSecondCapture();
      final ImageCaptureInstruction vista = c.secondInstruction;
      plano.proxima = ImageCaptureInstruction.sideView; // o plano muda de ideia

      expect(c.secondInstruction, vista,
          reason: 'a instrução não pode mudar com a câmera aberta');
    });

    test('reset limpa as duas fotografias', () async {
      final IdentificationController c = montar();
      await duasFotos(c);

      c.reset();

      expect(c.pendingImage, isNull);
      expect(c.secondImage, isNull);
      expect(c.isCapturingSecond, isFalse);
      expect(c.lastResult, isNull);
      expect(c.currentInstruction.captureType, CaptureType.topView);
    });
  });

  // ===========================================================================
  // O desfecho
  // ===========================================================================

  group('desfecho com duas vistas', () {
    test('o registro guarda a segunda vista e o que foi pedido nela', () async {
      final IdentificationController c = montar();
      await duasFotos(c);

      final IdentificationResult r = c.lastResult!;
      expect(r.viewCount, 2);
      expect(r.secondaryView, isNotNull);
      // Sem medição (imagem simulada), o plano cai no padrão: a cauda.
      expect(r.secondaryView!.captureType, CaptureType.tail);
    });

    test('quando as vistas concordam, mostra a espécie e diz que concordaram',
        () async {
      final IdentificationController c = montar(disagreement: 0.0);
      await duasFotos(c);

      expect(c.state, isA<IdentificationSuccess>());
      final IdentificationResult r = c.lastResult!;
      expect(r.isRejected, isFalse);
      expect(r.multiView, isNotNull);
      expect(r.multiView!.usedBothViews, isTrue);
      expect(r.multiView!.agreeOnTop1, isTrue);
      expect(r.top.species.id, MockSpecies.tityusSerrulatus.id);
    });

    test('quando as vistas DISCORDAM, não escolhe uma em silêncio', () async {
      // O motivo de existir uma segunda foto. Se a fusão simplesmente ficasse
      // com a hipótese de maior score, a discordância seria invisível — e o
      // usuário veria uma espécie apresentada com a mesma firmeza de sempre.
      final IdentificationController c = montar(disagreement: 1.0);
      await duasFotos(c);

      expect(c.state, isA<IdentificationRejected>());
      final IdentificationResult r = c.lastResult!;
      expect(r.rejectionReason, RejectionReason.ambiguous);
      expect(r.multiView!.agreeOnTop1, isFalse);
      // O registro continua tendo as duas vistas: a recusa não apaga a
      // evidência de que duas fotos foram tiradas.
      expect(r.viewCount, 2);
    });

    test('o resumo declara que os limiares NÃO foram calibrados', () async {
      // Os cortes de "alta" e "baixa" confiança ainda são palpites: nenhum
      // modelo foi avaliado. Mostrar o nível sem avisar disso seria afirmar
      // uma precisão que ninguém mediu — e é a tela que precisa saber.
      final IdentificationController c = montar(disagreement: 0.0);
      await duasFotos(c);

      expect(c.lastResult!.multiView!.thresholdsCalibrated, isFalse);
    });

    test('com UMA foto não há resumo de fusão', () async {
      // `multiView` só existe quando houve o que fundir. Um resumo dizendo
      // "1 vista, concordância total" seria informação inventada.
      final IdentificationController c = montar();
      final CapturedImage foto = CapturedImage.simulated();
      c.stageImage(foto);
      await c.inspect(foto);
      await c.submit(foto);

      expect(c.lastResult!.viewCount, 1);
      expect(c.lastResult!.multiView, isNull);
    });

    test('primeira vista rejeitada segue rejeitada, sem fusão', () async {
      // Sem hipótese nenhuma não há o que fundir, e a segunda foto não
      // "ressuscita" uma primeira que o motor não soube ler.
      final IdentificationController c =
          montar(servico: _ServicoFixo(rejeitar: true));
      await duasFotos(c);

      expect(c.state, isA<IdentificationRejected>());
      expect(c.lastResult!.multiView, isNull);
      expect(c.lastResult!.viewCount, 2);
    });

    test('duas fotos também deixam um registro só no histórico', () async {
      final IdentificationController c = montar();
      await duasFotos(c);

      final List<IdentificationResult> historico = await repo.fetchHistory();
      expect(historico, hasLength(1));
      expect(historico.single.viewCount, 2);
    });
  });

  // ===========================================================================
  // Fora do modo de demonstração
  // ===========================================================================

  group('com infraestrutura de verdade', () {
    test('duas fotos são registradas, e NADA é inventado', () async {
      // Sem modelo, o estado honesto é "aguardando análise". As duas vistas
      // ficam guardadas; nenhuma espécie e nenhum resumo de fusão aparecem.
      final IdentificationController c = montar(demonstration: false);
      await duasFotos(c);

      expect(c.state, isA<IdentificationAwaitingModel>());
      final IdentificationResult r = c.lastResult!;
      expect(r.status, IdentificationStatus.processing);
      expect(r.viewCount, 2);
      expect(r.predictions, isEmpty);
      expect(r.multiView, isNull,
          reason: 'a conclusão da análise nasce no servidor, não aqui');
    });
  });

  // ===========================================================================
  // DemoMultiViewService, por si
  // ===========================================================================

  group('DemoMultiViewService', () {
    final List<SpeciesPrediction> primeira = <SpeciesPrediction>[
      SpeciesPrediction(species: MockSpecies.tityusSerrulatus, score: 0.90),
      SpeciesPrediction(species: MockSpecies.tityusBahiensis, score: 0.06),
      SpeciesPrediction(species: MockSpecies.tityusStigmurus, score: 0.04),
    ];

    test('usa a fusão e a decisão de PRODUÇÃO — só a entrada é simulada', () {
      final DemoFusionOutcome f = DemoMultiViewService(
        random: Random(3),
        disagreementRate: 0.0,
      ).combine(first: primeira, secondType: CaptureType.tail);

      expect(f.summary.viewCount, 2);
      expect(f.summary.agreement, inInclusiveRange(0.0, 1.0));
      // Os scores fundidos formam uma distribuição: somam 1.
      final double soma = f.predictions
          .fold<double>(0, (double a, SpeciesPrediction p) => a + p.score);
      expect(soma, closeTo(1.0, 1e-6));
    });

    test('preserva as espécies, sem inventar nenhuma', () {
      final DemoFusionOutcome f = DemoMultiViewService(
        random: Random(3),
        disagreementRate: 1.0,
      ).combine(first: primeira, secondType: CaptureType.tail);

      final Set<String> esperadas =
          primeira.map((SpeciesPrediction p) => p.species.id).toSet();
      expect(
        f.predictions.map((SpeciesPrediction p) => p.species.id).toSet(),
        esperadas,
      );
    });

    test('a discordância derruba a concordância medida', () {
      final DemoFusionOutcome concorda = DemoMultiViewService(
        random: Random(5),
        disagreementRate: 0.0,
      ).combine(first: primeira, secondType: CaptureType.tail);
      final DemoFusionOutcome discorda = DemoMultiViewService(
        random: Random(5),
        disagreementRate: 1.0,
      ).combine(first: primeira, secondType: CaptureType.tail);

      expect(concorda.summary.agreeOnTop1, isTrue);
      expect(discorda.summary.agreeOnTop1, isFalse);
      expect(discorda.summary.agreement, lessThan(concorda.summary.agreement));
      expect(discorda.showsSpecies, isFalse);
    });

    group('o que a qualidade da foto faz na fusão', () {
      DemoFusionOutcome com(
        ImageQuality segunda, {
        required FusionStrategy estrategia,
      }) =>
          DemoMultiViewService(
            random: Random(11),
            disagreementRate: 1.0,
            strategy: estrategia,
          ).combine(
            first: primeira,
            secondType: CaptureType.tail,
            firstQuality: ImageQuality.good,
            secondQuality: segunda,
          );

      double scoreDaPrimeiraHipotese(DemoFusionOutcome f) => f.predictions
          .firstWhere((SpeciesPrediction p) =>
              p.species.id == MockSpecies.tityusSerrulatus.id)
          .score;

      test('na estratégia por QUALIDADE, a vista ruim tem menos voz', () {
        // Com a segunda vista discordando, uma foto ruim move o resultado
        // menos que uma boa.
        expect(
          scoreDaPrimeiraHipotese(com(
            ImageQuality.poor,
            estrategia: FusionStrategy.qualityWeighted,
          )),
          greaterThan(scoreDaPrimeiraHipotese(com(
            ImageQuality.good,
            estrategia: FusionStrategy.qualityWeighted,
          ))),
        );
      });

      test('na estratégia PADRÃO, a qualidade não altera os scores fundidos',
          () {
        // Este teste existe porque a primeira versão dele afirmava o
        // contrário, e falhou.
        //
        // A estratégia padrão pondera pela CONFIANÇA de cada vista. O peso de
        // qualidade é calculado e viaja junto, mas a fusão não o lê — a
        // qualidade entra depois, na decisão. Fica travado aqui para que
        // ninguém (eu, inclusive) volte a descrever o sistema como fazendo o
        // que ele não faz. Se um dia a estratégia padrão mudar, este teste cai
        // e obriga a rever o que a documentação diz.
        expect(
          scoreDaPrimeiraHipotese(com(
            ImageQuality.poor,
            estrategia: FusionStrategy.confidenceWeighted,
          )),
          closeTo(
            scoreDaPrimeiraHipotese(com(
              ImageQuality.good,
              estrategia: FusionStrategy.confidenceWeighted,
            )),
            1e-9,
          ),
        );
      });
    });

    test('com uma hipótese só, não há como discordar', () {
      // Trocar a primeira pela segunda exige que exista uma segunda.
      final DemoFusionOutcome f = DemoMultiViewService(
        random: Random(1),
        disagreementRate: 1.0,
      ).combine(
        first: <SpeciesPrediction>[primeira.first],
        secondType: CaptureType.tail,
      );

      expect(f.summary.agreeOnTop1, isTrue);
    });
  });
}

// =============================================================================
// Dublês
// =============================================================================

/// Motor simulado com desfecho fixo, para que o teste não dependa de sorteio.
class _ServicoFixo implements IdentificationService {
  _ServicoFixo({this.rejeitar = false});

  final bool rejeitar;

  @override
  Future<IdentificationResult> identify(
    CapturedImage image, {
    void Function(int stageIndex)? onStage,
    int stageCount = 4,
  }) async {
    final String id = 'mock-fixo-${DateTime.now().microsecondsSinceEpoch}';
    if (rejeitar) {
      return IdentificationResult.rejected(
        id: id,
        image: image,
        isMock: true,
        reason: RejectionReason.lowImageQuality,
      );
    }
    return IdentificationResult.identified(
      id: id,
      image: image,
      isMock: true,
      predictions: <SpeciesPrediction>[
        SpeciesPrediction(species: MockSpecies.tityusSerrulatus, score: 0.90),
        SpeciesPrediction(species: MockSpecies.tityusBahiensis, score: 0.06),
        SpeciesPrediction(species: MockSpecies.tityusStigmurus, score: 0.04),
      ],
    );
  }
}

/// Plano cuja resposta pode ser trocada no meio do teste.
class _PlanoQueMuda implements CapturePlanService {
  ImageCaptureInstruction proxima = ImageCaptureInstruction.tail;

  @override
  ImageCaptureInstruction primary() => ImageCaptureInstruction.primary;

  @override
  ImageCaptureInstruction secondary({ImageQualityResult? primaryQuality}) =>
      proxima;
}

class _Auth implements AuthRepository {
  @override
  AppUser? get currentUser =>
      const AppUser(id: 'uid-teste', name: 'Teste', email: 't@exemplo.test');

  // O fluxo de identificação só consulta `currentUser`. O resto lança de
  // propósito: se o controlador passar a usar outro método, o teste diz onde.
  @override
  Stream<AppUser?> authStateChanges() => throw UnimplementedError();

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
  Future<void> signOut() => throw UnimplementedError();

  @override
  Future<void> sendEmailVerification() => throw UnimplementedError();

  @override
  Future<AppUser?> reload() => throw UnimplementedError();

  @override
  Future<void> reauthenticate(String password) => throw UnimplementedError();

  @override
  Future<String?> idToken({bool forceRefresh = false}) =>
      throw UnimplementedError();

  @override
  void dispose() {}
}
