import 'package:flutter/material.dart';

/// Escorpião animado — o único arquivo de imagem do aplicativo.
///
/// # Formato
/// WebP animado com canal alfa, exibido por `Image.asset`. A escolha tem
/// motivo: o Flutter decodifica WebP animado nativamente em Android, iOS e web,
/// sem plugin, sem `WebView` e sem renderizador 3D. Num aparelho de dois
/// núcleos sem GPU, um renderizador ao vivo custaria muito mais do que o
/// resultado justifica — e o resultado seria diferente em cada aparelho, em
/// vez de idêntico em todos.
///
/// # Sobre o recorte
/// O vídeo de origem vinha sobre fundo cinza uniforme. Traço e sombra foram
/// separados na conversão: pixels neutros viraram **preto com opacidade
/// proporcional ao quanto escurecem**. Por isso a sombra existe sobre o tema
/// claro e desaparece sozinha no tema escuro, em vez de virar uma mancha
/// cinza recortada.
///
/// # Movimento reduzido
/// Quando o sistema pede menos animação, [reducedMotionFallback] entra no
/// lugar. Não é detalhe de acabamento: uma imagem que se mexe sem parar é
/// exatamente o que a preferência existe para desligar.
class ScorpionAnimation extends StatelessWidget {
  const ScorpionAnimation({
    super.key,
    required this.reducedMotionFallback,
    this.semanticLabel = 'Ilustração animada de um escorpião',
  });

  /// Exibido quando o sistema pede movimento reduzido.
  final Widget reducedMotionFallback;

  final String semanticLabel;

  /// Caminho único do arquivo. Em um lugar só para que trocar a arte não
  /// exija caçar literais por aí.
  static const String assetPath = 'assets/animations/scorpion_idle.webp';

  /// Largura real do arquivo, em pixels.
  ///
  /// Usada como `cacheWidth` para que o Flutter nunca guarde na memória uma
  /// versão maior do que existe: sem isso, um quadro esticado para caber num
  /// tablet seria decodificado no tamanho esticado, quadro a quadro.
  static const int intrinsicWidth = 340;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return reducedMotionFallback;
    }

    return Semantics(
      image: true,
      label: semanticLabel,
      child: Image.asset(
        assetPath,
        cacheWidth: intrinsicWidth,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
        // Se o arquivo faltar num build mal empacotado, a tela continua de pé
        // com a arte vetorial em vez de mostrar o ícone de imagem quebrada.
        errorBuilder: (_, _, _) =>
            reducedMotionFallback,
      ),
    );
  }
}
