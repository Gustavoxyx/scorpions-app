import 'package:flutter/widgets.dart';

/// Tokens de dimensão: ícones, alturas de controle, avatares, miniaturas.
///
/// A auditoria da Fase 1 encontrou 52 `size:` e 48 `width:/height:` numéricos
/// espalhados. Espaçamento já tinha escala; **tamanho de elemento não tinha** —
/// por isso um ícone aparecia com 17, 19, 20 e 21 em telas diferentes, sem que
/// nada justificasse a diferença. Estes tokens fecham isso.
abstract final class AppSizing {
  // -- Ícones -----------------------------------------------------------------
  // Poucos degraus, propositalmente. Ícone é sinal, não ilustração.

  /// Dentro de badges e etiquetas.
  static const double iconXs = 12;

  /// Ao lado de texto pequeno (metadados, chips).
  static const double iconSm = 14;

  /// Padrão: linhas de lista, cabeçalhos de seção.
  static const double iconMd = 18;

  /// Ações: botões, barra de navegação.
  static const double iconLg = 22;

  /// Ícone de destaque dentro de um contêiner colorido.
  static const double iconXl = 28;

  /// Ilustrativo: estados vazios, telas de erro.
  static const double iconHero = 36;

  // -- Alturas de controle ----------------------------------------------------

  static const double buttonSmall = 38;
  static const double buttonMedium = 46;
  static const double buttonLarge = 54;

  /// Campo de texto (com folga interna para o rótulo flutuante).
  static const double field = 52;

  /// Barra de navegação inferior flutuante.
  static const double navBar = 64;

  /// Cabeçalho de tela.
  static const double topBar = 56;

  /// Alvo mínimo de toque recomendado por acessibilidade (brief §34).
  /// Nenhum elemento clicável deve ficar abaixo disto.
  static const double minTouchTarget = 48;

  // -- Contêineres de ícone ---------------------------------------------------

  /// Quadrado colorido que abriga um ícone em cards e linhas.
  static const double iconTileSmall = 34;
  static const double iconTileMedium = 44;

  // -- Avatar -----------------------------------------------------------------

  static const double avatarSmall = 32;
  static const double avatarMedium = 44;
  static const double avatarLarge = 72;
  static const double avatarHero = 96;

  // -- Miniaturas e mídia -----------------------------------------------------

  /// Miniatura em linha de histórico compacta.
  static const double thumbSmall = 60;

  /// Miniatura padrão de card.
  static const double thumbMedium = 72;

  /// Placa de espécie em grade.
  static const double thumbLarge = 96;

  /// Botão de captura da câmera.
  static const double shutter = 74;
  static const double shutterInner = 60;

  // -- Traços -----------------------------------------------------------------

  static const double hairline = 1;
  static const double borderThick = 1.5;

  /// Espessura de anéis e medidores.
  static const double ringStroke = 8;

  // -- Larguras de conteúdo ---------------------------------------------------

  /// Acima disto o conteúdo para de esticar e centraliza: linha de texto muito
  /// longa prejudica leitura. O produto é mobile (brief §33); telas largas
  /// recebem a mesma coluna, centralizada.
  static const double maxContentWidth = 620;

  /// Largura máxima da barra de navegação flutuante.
  static const double maxNavWidth = 460;

  // -- Pontos de quebra -------------------------------------------------------

  /// Abaixo disto: Android pequeno. Reduz respiro e tamanho de títulos.
  static const double breakpointCompact = 360;

  /// Acima disto: tablet. Conteúdo centralizado, grades com mais colunas.
  static const double breakpointExpanded = 720;

  /// Altura abaixo da qual ilustrações precisam encolher para não estourar.
  static const double breakpointShort = 700;

  // -- Utilitários ------------------------------------------------------------

  /// Garante que uma área clicável respeite o alvo mínimo de toque.
  static BoxConstraints get touchTarget => const BoxConstraints(
        minWidth: minTouchTarget,
        minHeight: minTouchTarget,
      );
}
