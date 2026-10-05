import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../data/models/captured_image.dart';
import '../../data/models/species.dart';
import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'scorpion_mark.dart';

/// Placa ilustrativa de uma espécie.
///
/// A Fase 1 não tem fotografias licenciadas, e um cinza vazio faria o catálogo
/// parecer inacabado. Em vez disso geramos uma placa determinística a partir de
/// `Species.accentSeed`: cada espécie recebe sempre o mesmo campo de cor e a
/// mesma trama, o que dá identidade visual estável sem nenhum asset. Quando as
/// fotos chegarem (Fase 7), basta preencher `Species.imageAsset`.
class SpeciesPlate extends StatelessWidget {
  const SpeciesPlate({
    super.key,
    required this.species,
    this.borderRadius = AppRadii.brMd,
    this.markScale = 0.52,
  });

  final Species species;
  final BorderRadius borderRadius;
  final double markScale;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final double hueShift = (species.accentSeed % 60) - 30;
    final HSLColor base = HSLColor.fromColor(c.primary);
    final Color tint = base
        .withHue((base.hue + hueShift) % 360)
        .withSaturation((base.saturation * 0.7).clamp(0.0, 1.0))
        .toColor();

    return ClipRRect(
      borderRadius: borderRadius,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double side = math.min(
            constraints.maxWidth.isFinite ? constraints.maxWidth : 120,
            constraints.maxHeight.isFinite ? constraints.maxHeight : 120,
          );
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Color.lerp(c.surfaceVariant, tint, 0.16)!,
                      Color.lerp(c.surfaceSunken, tint, 0.04)!,
                    ],
                  ),
                ),
              ),
              CustomPaint(
                painter: _GridPainter(
                  color: c.textPrimary.withValues(alpha: 0.05),
                  seed: species.accentSeed,
                ),
              ),
              Center(
                child: ScorpionMark(
                  size: side * markScale,
                  color: tint.withValues(alpha: 0.55),
                  strokeScale: 0.9,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Trama de fundo: uma retícula de coleção científica, deslocada pela semente
/// para que duas espécies vizinhas não fiquem idênticas.
class _GridPainter extends CustomPainter {
  _GridPainter({required this.color, required this.seed});

  final Color color;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const double step = 14;
    final double offset = (seed % 7).toDouble();

    for (double x = -offset; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = -offset; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.color != color || old.seed != seed;
}

/// Exibe a foto capturada pelo usuário.
///
/// Quando não há arquivo (modo simulado, desktop sem câmera, teste), desenha um
/// espécime genérico para que o fluxo continue legível.
class CapturedPhoto extends StatelessWidget {
  const CapturedPhoto({
    super.key,
    required this.image,
    this.remoteUrl,
    this.borderRadius = AppRadii.brLg,
    this.fit = BoxFit.cover,
  });

  final CapturedImage? image;

  /// Endereço a usar no lugar de `image.url`.
  ///
  /// Existe para que uma lista possa pedir a **miniatura** em vez da imagem
  /// de análise. Sem isso, rolar o histórico baixaria a foto inteira de cada
  /// item — que é justamente o desperdício que gerar a miniatura evita.
  final String? remoteUrl;

  final BorderRadius borderRadius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final CapturedImage? img = image;
    final String? url = remoteUrl ?? img?.url;

    // A ordem é por custo, do mais barato ao mais caro: o que já está na
    // memória, depois o que está em disco, depois o que exige rede.
    //
    // O ramo da rede faltava até a Fase 4, e o efeito era silencioso e feio:
    // `IdentificationResult.fromMap` monta `CapturedImage.remote(url: …)` e o
    // comentário de lá diz "a tela usa a URL" — só que esta tela nunca a
    // lia. Toda identificação reaberta do banco caía no placeholder e exibia
    // "Imagem simulada", o que não é só uma falta: é uma informação falsa
    // sobre uma foto que existe e já foi paga em banda de upload.
    Widget content;
    if (img != null && img.hasBytes) {
      content = Image.memory(img.bytes!, fit: fit);
    } else if (img != null && img.hasFile && !kIsWeb) {
      content = Image.file(
        File(img.path!),
        fit: fit,
        // O caminho local é temporário: o sistema limpa o cache quando quer.
        // Se o arquivo sumiu mas a cópia remota existe, vale a rede.
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
            url == null ? _placeholder(context, c) : _remote(context, c, url),
      );
    } else if (url != null) {
      content = _remote(context, c, url);
    } else {
      content = _placeholder(context, c);
    }

    return ClipRRect(borderRadius: borderRadius, child: content);
  }

  Widget _remote(BuildContext context, AppColors c, String url) {
    return Image.network(
      url,
      fit: fit,
      // Enquanto baixa, o mesmo fundo do placeholder — sem rodinha, que numa
      // lista de miniaturas viraria um piscar de várias ao mesmo tempo.
      loadingBuilder: (
        BuildContext context,
        Widget child,
        ImageChunkEvent? progress,
      ) =>
          progress == null ? child : _surface(c),
      errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
          _placeholder(context, c),
    );
  }

  Widget _surface(AppColors c) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[c.surfaceVariant, c.surfaceSunken],
          ),
        ),
      );

  /// Texto do vazio.
  ///
  /// "Imagem simulada" só é verdade quando a identificação nasceu no modo de
  /// demonstração. Para uma foto real que não chegou — envio recusado, arquivo
  /// temporário já limpo, rede fora — dizer "simulada" é afirmar algo falso
  /// sobre o registro do usuário.
  String get _emptyLabel =>
      (image?.isSimulated ?? true) ? 'Imagem simulada' : 'Foto indisponível';

  Widget _placeholder(BuildContext context, AppColors c) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[c.surfaceVariant, c.surfaceSunken],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          CustomPaint(
            painter: _GridPainter(
              color: c.textPrimary.withValues(alpha: 0.04),
              seed: 3,
            ),
          ),
          Center(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double side = math.min(
                  constraints.maxWidth.isFinite ? constraints.maxWidth : 160,
                  constraints.maxHeight.isFinite ? constraints.maxHeight : 160,
                );
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ScorpionMark(
                      size: side * 0.34,
                      color: c.textTertiary.withValues(alpha: 0.55),
                    ),
                    if (side > 160) ...<Widget>[
                      AppSpacing.gapMd,
                      Text(
                        _emptyLabel,
                        style: context.text.overline
                            .copyWith(color: c.textTertiary),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
