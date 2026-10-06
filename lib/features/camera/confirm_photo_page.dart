import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_sizing.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/feedback_states.dart';
import '../../core/widgets/reveal.dart';
import '../../core/widgets/specimen_image.dart';
import '../../data/models/capture_instruction.dart';
import '../../data/models/captured_image.dart';
import '../../data/models/processed_image.dart';
import '../../state/identification_controller.dart';
import 'widgets/frame_guide.dart';
import 'widgets/photo_quality_notice.dart';

/// Confirmação das fotos antes da análise.
///
/// É um passo curto mas importante do produto: dá ao usuário a chance de
/// descartar uma foto ruim ANTES de gastar a análise.
///
/// # A segunda foto é oferecida aqui, não imposta
/// Depois que a primeira passa na inspeção, a tela convida para uma segunda —
/// e diz **qual**, e por quê. A instrução vem do plano de captura, que a
/// escolhe a partir do que foi medido na primeira: foto nítida pede a cauda,
/// onde está a serrilha que separa espécies parecidas; foto no limite do foco
/// pede o perfil, porque um close sairia pior ainda.
///
/// Seguir com uma foto só continua sendo um caminho de primeira classe. O
/// animal pode ter fugido, a pessoa pode não querer chegar mais perto, e uma
/// identificação com uma vista vale mais que nenhuma. Por isso "analisar só
/// esta" é um botão, e não um link escondido.
class ConfirmPhotoPage extends StatefulWidget {
  const ConfirmPhotoPage({super.key});

  @override
  State<ConfirmPhotoPage> createState() => _ConfirmPhotoPageState();
}

class _ConfirmPhotoPageState extends State<ConfirmPhotoPage> {
  @override
  void initState() {
    super.initState();
    // A inspeção começa sozinha ao abrir a tela: o usuário já está olhando
    // para a foto, e esperar que ele toque em algo para só então descobrir que
    // ela está escura seria desperdiçar justamente o tempo em que ele decide.
    WidgetsBinding.instance.addPostFrameCallback((_) => _inspecionar());
  }

  Future<void> _inspecionar() async {
    if (!mounted) return;
    final IdentificationController c = context.read<IdentificationController>();
    final CapturedImage? imagem = c.pendingImage;
    if (imagem == null || c.preparation != null) return;
    await c.inspect(imagem);
  }

  /// Abre a câmera para a segunda fotografia e, na volta, inspeciona-a.
  ///
  /// A inspeção acontece aqui, depois do `await`, e não dentro de `build`:
  /// disparar trabalho assíncrono a partir da construção da tela faria cada
  /// reconstrução tentar inspecionar de novo.
  Future<void> _adicionarSegunda() async {
    final IdentificationController c = context.read<IdentificationController>();
    c.beginSecondCapture();
    await context.push(AppRoutes.capture);

    if (!mounted) return;
    if (c.secondImage != null && c.secondPreparation == null) {
      await c.inspectSecond();
    }
  }

  void _analisar(IdentificationController c, CapturedImage primeira) {
    c.submit(primeira);
    context.pushReplacement(AppRoutes.analyzing);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final IdentificationController controller =
        context.watch<IdentificationController>();
    final CapturedImage? image = controller.pendingImage;

    // Salvaguarda: se a página for aberta sem imagem pendente (por exemplo,
    // após um hot-restart), voltamos para a captura em vez de quebrar.
    if (image == null) {
      return Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: ErrorState(
            title: 'Nenhuma foto',
            message: 'A imagem não está mais disponível. Capture novamente.',
            onRetry: () => context.pushReplacement(AppRoutes.capture),
          ),
        ),
      );
    }

    final CapturedImage? segunda = controller.secondImage;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.maxContentWidth),
            // A tela se ajusta à altura disponível e, quando não cabe, rola.
            //
            // Com a oferta da segunda foto, a parte de baixo ficou mais alta.
            // Num aparelho baixo, ou com a fonte do sistema ampliada, uma
            // `Column` com a foto em `Expanded` transbordaria — a foto seria
            // espremida até zero e os botões sairiam da tela. Assim a foto
            // ocupa o que sobra quando sobra, e mantém uma altura mínima
            // quando não sobra.
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints limites) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: limites.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        children: <Widget>[
                          _Cabecalho(
                            titulo: segunda == null
                                ? AppStrings.confirmTitle
                                : 'Duas fotos',
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.screenGutter,
                              ),
                              child: ConstrainedBox(
                                // Piso de altura para quando a tela rola. Baixo
                                // de propósito: em aparelho pequeno, cada
                                // ponto dado à foto é um ponto tirado dos
                                // botões, e é com eles que a pessoa decide.
                                constraints:
                                    const BoxConstraints(minHeight: 160),
                                child: Reveal(
                                  child: segunda == null
                                      ? _Foto(image: image, comMoldura: true)
                                      : Row(
                                          children: <Widget>[
                                            Expanded(
                                              child: _Foto(
                                                image: image,
                                                rotulo: '1',
                                              ),
                                            ),
                                            AppSpacing.gapSm,
                                            Expanded(
                                              child: _Foto(
                                                image: segunda,
                                                rotulo: '2',
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.all(AppSpacing.screenGutter),
                            child: segunda == null
                                ? _AcoesPrimeiraFoto(
                                    controller: controller,
                                    onAdicionarSegunda: _adicionarSegunda,
                                    onAnalisar: () =>
                                        _analisar(controller, image),
                                  )
                                : _AcoesDuasFotos(
                                    controller: controller,
                                    onRefazerSegunda: () {
                                      controller.discardSecondImage();
                                      _adicionarSegunda();
                                    },
                                    onAnalisar: () =>
                                        _analisar(controller, image),
                                    onSoAPrimeira: () {
                                      controller.discardSecondImage();
                                      _analisar(controller, image);
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.titulo});

  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      child: Row(
        children: <Widget>[
          AppIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: AppStrings.back,
            size: AppSizing.minTouchTarget - AppSpacing.sm,
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            // Uma linha só, encolhendo a fonte se preciso.
            //
            // Num aparelho estreito o título disputa a largura com o selo de
            // dado simulado. Deixá-lo quebrar dobraria a altura do cabeçalho e
            // empurraria os botões para fora da tela; cortá-lo com reticências
            // — a primeira tentativa — deixava "Foto captura…" em 360 pontos
            // de largura, que é um tamanho comum. `scaleDown` só age quando
            // não cabe, e nunca aumenta.
            //
            // O respiro até o selo fica DENTRO da área flexível, como margem, e
            // não como um espaço fixo ao lado: com a fonte do sistema ampliada
            // o selo cresce, e um espaço fixo a mais fazia a linha transbordar
            // por três pontos. Aqui ele cede junto com o título.
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(titulo, maxLines: 1, style: context.text.h2),
              ),
            ),
          ),
          const MockDataBadge(compact: true),
        ],
      ),
    );
  }
}

/// Uma fotografia, com a moldura de referência ou com o número da vista.
class _Foto extends StatelessWidget {
  const _Foto({required this.image, this.comMoldura = false, this.rotulo});

  final CapturedImage image;

  /// A mesma moldura da câmera, agora só como referência. Só na foto única:
  /// lado a lado, duas molduras disputariam a atenção com as imagens.
  final bool comMoldura;

  /// "1" ou "2", quando há duas — para o aviso de qualidade poder dizer de
  /// qual está falando.
  final String? rotulo;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Stack(
      children: <Widget>[
        Positioned.fill(child: CapturedPhoto(image: image)),
        if (comMoldura)
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: FrameGuide(color: c.onMedia, opacity: 0.35, thickness: 2),
            ),
          ),
        if (rotulo != null)
          Positioned(
            top: AppSpacing.sm,
            left: AppSpacing.sm,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: c.scrim,
                borderRadius: AppRadii.brMd,
              ),
              child: Text(
                rotulo!,
                style: context.text.label.copyWith(color: c.onMedia),
              ),
            ),
          ),
      ],
    );
  }
}

/// Ações com uma foto só: oferecer a segunda, ou seguir sem ela.
class _AcoesPrimeiraFoto extends StatelessWidget {
  const _AcoesPrimeiraFoto({
    required this.controller,
    required this.onAdicionarSegunda,
    required this.onAnalisar,
  });

  final IdentificationController controller;
  final VoidCallback onAdicionarSegunda;
  final VoidCallback onAnalisar;

  @override
  Widget build(BuildContext context) {
    final ImagePreparation? prep = controller.preparation;
    final bool inspecionando = controller.state is IdentificationInspecting;
    final bool podeSeguir = prep?.canProceed ?? false;
    final bool temRessalva =
        podeSeguir && (prep!.quality?.warnings.isNotEmpty ?? false);

    return Column(
      children: <Widget>[
        PhotoQualityNotice(preparation: prep),
        if (podeSeguir) ...<Widget>[
          AppSpacing.gapMd,
          _ConviteSegundaFoto(instruction: controller.secondInstruction),
        ],
        AppSpacing.gapLg,
        AppButton(
          label: 'Adicionar segunda foto',
          icon: Icons.add_a_photo_outlined,
          // O halo é da ação recomendada. Com foto ruim, a recomendação deixa
          // de ser "acrescente outra" e passa a ser "refaça esta" — então o
          // destaque sai.
          glow: podeSeguir && !temRessalva,
          loading: inspecionando,
          onPressed: podeSeguir ? onAdicionarSegunda : null,
        ),
        AppSpacing.gapSm,
        Row(
          children: <Widget>[
            Expanded(
              child: AppButton(
                // O rótulo muda quando há ressalva: "usar mesmo assim" diz que
                // a pessoa está escolhendo seguir apesar do aviso, que é
                // exatamente o que o §6 pede.
                label:
                    temRessalva ? AppStrings.usePhotoAnyway : 'Analisar só esta',
                size: AppButtonSize.medium,
                variant: AppButtonVariant.secondary,
                onPressed: podeSeguir ? onAnalisar : null,
              ),
            ),
            AppSpacing.gapSm,
            Expanded(
              child: AppButton(
                label: AppStrings.retakePhoto,
                icon: Icons.replay_rounded,
                size: AppButtonSize.medium,
                variant: AppButtonVariant.ghost,
                onPressed: () {
                  controller.discardPendingImage();
                  context.pop();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Diz qual segunda foto vale a pena, antes de a pessoa decidir.
///
/// O convite mostra a instrução — o quê e como — porque "adicionar segunda
/// foto" sozinho não diz nada: a pessoa precisa saber que vai ter de chegar
/// perto da cauda **antes** de aceitar, não depois de a câmera abrir.
class _ConviteSegundaFoto extends StatelessWidget {
  const _ConviteSegundaFoto({required this.instruction});

  final ImageCaptureInstruction instruction;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.primarySoft,
        borderRadius: AppRadii.brMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.tips_and_updates_outlined, color: c.primary, size: 20),
          AppSpacing.gapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // "Opcional" vem primeiro, antes do pedido: a pessoa precisa
                // saber que pode recusar antes de ler o que se pede dela.
                Text(
                  'SEGUNDA FOTO · OPCIONAL',
                  style: context.text.overlineSmall
                      .copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xs),
                // O título da própria instrução, e não uma frase genérica
                // sobre "espécies parecidas" — que a descrição logo abaixo já
                // diz, com o motivo concreto.
                Text(instruction.title, style: context.text.label),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  instruction.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style:
                      context.text.caption.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ações com as duas fotos tiradas.
class _AcoesDuasFotos extends StatelessWidget {
  const _AcoesDuasFotos({
    required this.controller,
    required this.onRefazerSegunda,
    required this.onAnalisar,
    required this.onSoAPrimeira,
  });

  final IdentificationController controller;
  final VoidCallback onRefazerSegunda;
  final VoidCallback onAnalisar;
  final VoidCallback onSoAPrimeira;

  @override
  Widget build(BuildContext context) {
    final ImagePreparation? prep = controller.secondPreparation;
    final bool inspecionando = controller.state is IdentificationInspecting;
    final bool segundaServe = controller.hasSecondView;

    return Column(
      children: <Widget>[
        // O aviso aqui é sobre a SEGUNDA foto: a primeira já foi aceita na
        // etapa anterior, e repetir o veredito dela só ocuparia espaço.
        PhotoQualityNotice(preparation: prep),
        AppSpacing.gapLg,
        AppButton(
          label: 'Analisar as duas fotos',
          icon: Icons.check_rounded,
          glow: segundaServe,
          loading: inspecionando,
          onPressed: segundaServe ? onAnalisar : null,
        ),
        AppSpacing.gapSm,
        Row(
          children: <Widget>[
            Expanded(
              child: AppButton(
                label: 'Refazer a 2ª',
                icon: Icons.replay_rounded,
                size: AppButtonSize.medium,
                variant: AppButtonVariant.secondary,
                onPressed: inspecionando ? null : onRefazerSegunda,
              ),
            ),
            AppSpacing.gapSm,
            Expanded(
              child: AppButton(
                // Sempre disponível, inclusive quando a segunda foi recusada:
                // uma segunda foto que não serviu não pode prender a pessoa. A
                // primeira já foi aceita, e uma vista ruim não invalida a
                // identificação se a outra tem informação suficiente (§5).
                label: 'Só a 1ª',
                size: AppButtonSize.medium,
                variant: AppButtonVariant.ghost,
                onPressed: inspecionando ? null : onSoAPrimeira,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
