import 'package:flutter_test/flutter_test.dart';
import 'package:scorpions/data/models/capture_instruction.dart';
import 'package:scorpions/data/models/image_quality.dart';
import 'package:scorpions/data/services/capture_plan_service.dart';

/// Testes de `HeuristicCapturePlanService`.
///
/// # Por que este arquivo existe
/// A auditoria de otimização achou este serviço como o único arquivo de `lib/`
/// que nada importava — nem o aplicativo nem os testes (achado M-1). Ele não é
/// código morto: foi escrito para a tela de duas fotos da Fase 5, que ainda não
/// existe.
///
/// Mas código sem consumidor **e** sem teste é código que ninguém sabe se
/// funciona. Quando a tela chegar, ninguém descobre o defeito a tempo. Então o
/// teste vem antes do consumidor.
///
/// # O que está sendo verificado
/// A regra tem uma inversão deliberada que é fácil de "corrigir" por engano:
/// foto no limite da nitidez pede **perfil**, não close. Quem ler a regra sem o
/// comentário pode achar que está invertida e trocar. O teste trava a decisão.
void main() {
  const HeuristicCapturePlanService plano = HeuristicCapturePlanService();

  /// Medição de qualidade com os avisos que o caso precisa.
  ///
  /// Os valores numéricos são plausíveis mas irrelevantes: a decisão olha só a
  /// lista de avisos. Mantê-los realistas evita que um teste futuro passe a
  /// depender de um número inventado aqui.
  ImageQualityResult medicao(List<ImageQualityWarning> avisos) {
    return ImageQualityResult(
      quality: avisos.isEmpty ? ImageQuality.good : ImageQuality.acceptable,
      score: avisos.isEmpty ? 0.86 : 0.54,
      brightness: 0.45,
      contrast: 0.12,
      sharpness: avisos.isEmpty ? 0.0061 : 0.0022,
      width: 1600,
      height: 1200,
      warnings: avisos,
    );
  }

  group('primeira instrução', () {
    test('é sempre a mesma, independente de qualquer coisa', () {
      // Não depende de entrada nenhuma: na primeira foto não há o que medir
      // ainda. Se isso mudar, é decisão de produto, não refinamento.
      expect(plano.primary(), ImageCaptureInstruction.primary);
      expect(plano.primary().captureType, CaptureType.topView);
    });
  });

  group('segunda instrução', () {
    test('sem medição, cai no padrão: a cauda', () {
      // Primeira imagem simulada — modo de demonstração, desktop, teste. Sem
      // medição não há sinal, e o padrão é a vista de maior poder de separação.
      expect(
        plano.secondary().captureType,
        CaptureType.tail,
      );
      expect(
        plano.secondary(primaryQuality: null).captureType,
        CaptureType.tail,
      );
    });

    test('foto nítida e bem exposta pede a cauda', () {
      final ImageCaptureInstruction segunda = plano.secondary(
        primaryQuality: medicao(const <ImageQualityWarning>[]),
      );

      expect(segunda.captureType, CaptureType.tail);
    });

    test('foto desfocada pede o PERFIL, não um close', () {
      // A inversão deliberada, e o motivo de este teste existir.
      //
      // Um aparelho que não conseguiu focar o animal inteiro vai falhar pior
      // numa aproximação, onde a profundidade de campo é menor. Pedir o close
      // produziria uma segunda foto pior que a primeira, e duas imagens ruins
      // não somam.
      for (final ImageQualityWarning aviso in <ImageQualityWarning>[
        ImageQualityWarning.blurry,
        ImageQualityWarning.softFocus,
      ]) {
        final ImageCaptureInstruction segunda = plano.secondary(
          primaryQuality: medicao(<ImageQualityWarning>[aviso]),
        );

        expect(
          segunda.captureType,
          CaptureType.generalSideView,
          reason:
              'com $aviso a segunda foto precisa ser o perfil: um close sobre '
              'uma primeira foto mole sai pior que ela',
        );
      }
    });

    test('resolução baixa pede o perfil, pelo mesmo motivo', () {
      // Não há pixels suficientes na região para o detalhe aparecer — efeito
      // prático idêntico ao do desfoque num close.
      final ImageCaptureInstruction segunda = plano.secondary(
        primaryQuality: medicao(
          const <ImageQualityWarning>[ImageQualityWarning.lowResolution],
        ),
      );

      expect(segunda.captureType, CaptureType.generalSideView);
    });

    test('aviso que não fala de detalhe não desvia da cauda', () {
      // Exposição ruim prejudica cor, não resolução de detalhe. Desviar para o
      // perfil por causa dela seria generalizar a regra além do que ela sabe.
      for (final ImageQualityWarning aviso in <ImageQualityWarning>[
        ImageQualityWarning.tooDark,
        ImageQualityWarning.tooBright,
      ]) {
        expect(
          plano
              .secondary(
                primaryQuality: medicao(<ImageQualityWarning>[aviso]),
              )
              .captureType,
          CaptureType.tail,
          reason: '$aviso não é motivo para trocar a vista pedida',
        );
      }
    });

    test('desfoque vence quando aparece junto de outro aviso', () {
      // Ordem dos avisos não pode mudar a decisão: a limitação mais severa
      // manda.
      final ImageCaptureInstruction a = plano.secondary(
        primaryQuality: medicao(const <ImageQualityWarning>[
          ImageQualityWarning.tooDark,
          ImageQualityWarning.blurry,
        ]),
      );
      final ImageCaptureInstruction b = plano.secondary(
        primaryQuality: medicao(const <ImageQualityWarning>[
          ImageQualityWarning.blurry,
          ImageQualityWarning.tooDark,
        ]),
      );

      expect(a.captureType, CaptureType.generalSideView);
      expect(b.captureType, CaptureType.generalSideView);
    });
  });

  group('as instruções são apresentáveis ao usuário', () {
    test('toda instrução que o serviço pode devolver tem texto', () {
      // Uma instrução sem texto chegaria à tela como espaço em branco, e o
      // usuário não saberia o que fotografar. Vale para todas as saídas
      // possíveis, não só as do caminho feliz.
      final List<ImageCaptureInstruction> possiveis =
          <ImageCaptureInstruction>[
        plano.primary(),
        plano.secondary(),
        plano.secondary(primaryQuality: medicao(const <ImageQualityWarning>[])),
        plano.secondary(
          primaryQuality: medicao(
            const <ImageQualityWarning>[ImageQualityWarning.blurry],
          ),
        ),
      ];

      for (final ImageCaptureInstruction i in possiveis) {
        expect(i.title, isNotEmpty, reason: '${i.captureType} sem título');
        expect(
          i.description,
          isNotEmpty,
          reason: '${i.captureType} sem descrição',
        );
      }
    });
  });
}
