import 'package:flutter/foundation.dart';

/// O que a fotografia precisa mostrar.
///
/// # Por que isto é um tipo e não um texto na tela
/// O briefing (§3) é explícito em não assumir que a segunda foto será sempre
/// a mesma região. A escolha depende da primeira imagem, da qualidade dela e
/// — quando o modelo existir — das espécies candidatas: separar *Tityus
/// serrulatus* de *Tityus bahiensis* pede o dorso e a serrilha da cauda,
/// enquanto distinguir Buthidae de Bothriuridae se resolve pelos pedipalpos.
///
/// Com o tipo, a instrução vira dado que o pipeline escolhe. Com um texto
/// fixo na tela de captura, a decisão ficaria presa na interface e qualquer
/// evolução exigiria mexer em widget.
enum CaptureType {
  /// Dorso, animal inteiro. É a vista que mais carrega informação geral.
  topView('top_view'),

  /// Aproximação sem região definida — quando só se sabe que falta detalhe.
  closeUp('close_up'),

  /// Pedipalpos (as pinças). Proporção e granulação separam famílias.
  pedipalp('pedipalp'),

  /// Metassoma. A serrilha dos últimos segmentos é diagnóstica em *Tityus*.
  tail('tail'),

  /// Télson — vesícula e acúleo. A presença de apófise subaculear distingue
  /// espécies próximas.
  telson('telson'),

  /// Perfil do animal inteiro.
  generalSideView('general_side_view');

  const CaptureType(this.id);

  final String id;

  static CaptureType fromId(String? raw) {
    for (final CaptureType t in CaptureType.values) {
      if (t.id == raw) return t;
    }
    return CaptureType.topView;
  }
}

/// Região do quadro que a instrução pede em foco.
///
/// Normalizada de 0 a 1 pelo mesmo motivo de `BoundingBox`: a mesma região
/// precisa valer para o visor da câmera, para a imagem processada e para a
/// miniatura, que têm resoluções diferentes.
@immutable
class TargetRegion {
  const TargetRegion({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// O quadro inteiro. Usado quando a instrução não aponta para uma parte.
  const TargetRegion.full()
      : left = 0,
        top = 0,
        width = 1,
        height = 1;

  /// Faixa central, mais alta que larga — serve para cauda e télson, que são
  /// alongados.
  const TargetRegion.centerStrip()
      : left = 0.25,
        top = 0.15,
        width = 0.5,
        height = 0.7;

  final double left;
  final double top;
  final double width;
  final double height;

  bool get isFull => left == 0 && top == 0 && width == 1 && height == 1;

  Map<String, Object?> toMap() => <String, Object?>{
        'left': left,
        'top': top,
        'width': width,
        'height': height,
      };
}

/// Uma orientação de captura apresentada ao usuário.
///
/// # Sobre o texto
/// [title] e [description] moram aqui, e não em `AppStrings`, porque uma
/// instrução é uma unidade: mudar o alvo sem mudar o texto produziria uma tela
/// pedindo uma coisa e desenhando outra. O preço é que a localização futura
/// precisará passar por este arquivo — aceito, porque o erro que isso evita é
/// pior que o incômodo que causa.
@immutable
class ImageCaptureInstruction {
  const ImageCaptureInstruction({
    required this.id,
    required this.title,
    required this.description,
    required this.captureType,
    this.targetRegion = const TargetRegion.full(),
    this.priority = 0,
  });

  final String id;

  /// O pedido, em uma frase curta. É o que aparece grande no visor.
  final String title;

  /// Como conseguir a foto. Aparece abaixo, menor.
  final String description;

  final CaptureType captureType;

  /// Onde o enquadramento deve se concentrar.
  final TargetRegion targetRegion;

  /// Quanto esta vista contribui para separar espécies. Maior vence quando o
  /// plano precisa escolher. Fica em zero enquanto não houver medição — o
  /// briefing proíbe inventar número que não foi medido.
  final int priority;

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'captureType': captureType.id,
        'targetRegion': targetRegion.toMap(),
        'priority': priority,
      };

  // ---------------------------------------------------------------------------
  // Catálogo
  // ---------------------------------------------------------------------------

  /// Primeira foto. Sempre a mesma, para todo mundo.
  ///
  /// Não depende de nada porque é ela que produz a informação sobre a qual as
  /// decisões seguintes são tomadas.
  static const ImageCaptureInstruction primary = ImageCaptureInstruction(
    id: 'primary-top-view',
    title: 'Fotografe o escorpião de cima',
    description:
        'Mantenha o animal inteiro dentro da área indicada, com o aparelho '
        'paralelo ao chão.',
    captureType: CaptureType.topView,
  );

  static const ImageCaptureInstruction tail = ImageCaptureInstruction(
    id: 'secondary-tail',
    title: 'Agora aproxime a cauda',
    description:
        'Chegue mais perto e mantenha os últimos segmentos nítidos. É neles '
        'que está a serrilha que separa espécies parecidas.',
    captureType: CaptureType.tail,
    targetRegion: TargetRegion.centerStrip(),
  );

  static const ImageCaptureInstruction telson = ImageCaptureInstruction(
    id: 'secondary-telson',
    title: 'Aproxime o ferrão',
    description:
        'Enquadre a ponta da cauda — a vesícula e o acúleo. Segure firme: '
        'close desfocado não ajuda a análise.',
    captureType: CaptureType.telson,
    targetRegion: TargetRegion.centerStrip(),
  );

  static const ImageCaptureInstruction pedipalp = ImageCaptureInstruction(
    id: 'secondary-pedipalp',
    title: 'Aproxime as pinças',
    description:
        'Enquadre os pedipalpos. O formato e a espessura deles separam grupos '
        'inteiros de escorpiões.',
    captureType: CaptureType.pedipalp,
  );

  /// Vista de reserva, quando a primeira foto não permite pedir uma região.
  static const ImageCaptureInstruction sideView = ImageCaptureInstruction(
    id: 'secondary-side-view',
    title: 'Fotografe de lado',
    description:
        'Mude o ângulo e fotografe o animal de perfil, inteiro no quadro.',
    captureType: CaptureType.generalSideView,
  );

  static const List<ImageCaptureInstruction> secondaryOptions =
      <ImageCaptureInstruction>[tail, telson, pedipalp, sideView];
}
