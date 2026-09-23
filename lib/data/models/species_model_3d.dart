import 'package:flutter/foundation.dart';

/// Parte anatômica que pode ser destacada num modelo tridimensional.
///
/// Os nomes correspondem às estruturas que o brief §24 lista como tocáveis no
/// futuro. Existir como enum — e não como texto livre — garante que a mesma
/// parte tenha o mesmo identificador no modelo 3D, na ficha da espécie e, mais
/// adiante, nos dados vindos do backend.
enum AnatomyPart {
  pedipalps('Pedipalpos'),
  chela('Pinças'),
  metasoma('Cauda'),
  telson('Ferrão'),
  prosoma('Prossoma'),
  mesosoma('Abdome'),
  pectines('Pentes'),
  legs('Pernas');

  const AnatomyPart(this.label);

  final String label;
}

/// Ponto interativo sobre o modelo tridimensional.
///
/// A posição é normalizada (0–1) em vez de absoluta para que o mesmo ponto
/// funcione em qualquer resolução e em qualquer visualizador que venhamos a
/// adotar na Fase 7.
@immutable
class AnatomyHotspot {
  const AnatomyHotspot({
    required this.part,
    required this.description,
    this.x = 0.5,
    this.y = 0.5,
  });

  final AnatomyPart part;

  /// Explicação exibida ao tocar o ponto.
  final String description;

  final double x;
  final double y;

  String get label => part.label;
}

/// Referência a um modelo tridimensional de uma espécie.
///
/// # Estado nesta fase
/// Sempre nulo. Nenhum arquivo 3D foi incluído — o brief §13 é explícito em não
/// carregar modelos pesados só para preencher a interface, e o §12 pede
/// preparar a arquitetura sem construir o sistema.
///
/// # O que já está resolvido
/// O modelo de dados, o vocabulário anatômico ([AnatomyPart]) e o formato dos
/// pontos interativos. A tela de resultado e a ficha da espécie já consultam
/// `Species.has3DModel` para decidir entre mostrar o botão ativo ou o aviso de
/// "em breve" — então ligar o visualizador na Fase 7 é preencher este campo e
/// trocar o corpo de um único widget.
@immutable
class SpeciesModel3D {
  const SpeciesModel3D({
    required this.assetPath,
    this.hotspots = const <AnatomyHotspot>[],
    this.attribution,
    this.format = Model3DFormat.glb,
  });

  /// Caminho do arquivo empacotado ou URL remota.
  final String assetPath;

  /// Pontos anatômicos tocáveis sobre o modelo.
  final List<AnatomyHotspot> hotspots;

  /// Crédito de autoria/licença. Obrigatório para modelos de terceiros.
  final String? attribution;

  final Model3DFormat format;
}

enum Model3DFormat { glb, gltf, usdz }
