import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_config.dart';
import '../theme/app_theme.dart';

/// Marca do produto: uma silhueta vetorial de escorpião, vista de cima.
///
/// É desenhada com [CustomPainter] em vez de um arquivo de imagem por três
/// razões: escala sem perda em qualquer densidade de tela, acompanha a cor do
/// tema (claro/escuro) automaticamente e não adiciona peso ao bundle. O
/// desenho é feito num espaço de 100x100 e escalado para o tamanho pedido.
class ScorpionMark extends StatelessWidget {
  const ScorpionMark({
    super.key,
    this.size = 64,
    this.color,
    this.glow = 0,
    this.strokeScale = 1,
  });

  final double size;
  final Color? color;

  /// Intensidade do halo ultravioleta, de 0 a 1. Usado no splash.
  final double glow;

  /// Multiplicador da espessura das pernas e pinças.
  final double strokeScale;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _ScorpionPainter(
          color: color ?? context.colors.primary,
          glow: glow,
          strokeScale: strokeScale,
        ),
      ),
    );
  }
}

class _ScorpionPainter extends CustomPainter {
  _ScorpionPainter({
    required this.color,
    required this.glow,
    required this.strokeScale,
  });

  final Color color;
  final double glow;
  final double strokeScale;

  /// Espaço lógico do desenho.
  static const double _canvas = 100;

  @override
  void paint(Canvas canvas, Size size) {
    final double k = size.width / _canvas;
    canvas.save();
    canvas.scale(k);

    final Paint fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    if (glow > 0) {
      // O halo é a mesma silhueta redesenhada com desfoque atrás da principal.
      // Precisa de dois Paint distintos porque _drawBody alterna o estilo.
      final MaskFilter blur = MaskFilter.blur(BlurStyle.normal, 6 * glow);
      final Color haloColor = color.withValues(alpha: 0.55 * glow);
      _drawBody(
        canvas,
        Paint()
          ..color = haloColor
          ..maskFilter = blur
          ..isAntiAlias = true,
        Paint()
          ..color = haloColor
          ..maskFilter = blur
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true,
      );
    }

    _drawBody(canvas, fill, stroke);
    canvas.restore();
  }

  void _drawBody(Canvas canvas, Paint fill, Paint stroke) {
    // --- Pernas: quatro pares, espelhadas no eixo vertical -------------------
    stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1 * strokeScale;
    const List<List<double>> legs = <List<double>>[
      // [origemY, meioX, meioY, pontaX, pontaY]
      <double>[63, 32, 62, 22, 70],
      <double>[59, 31, 56, 20, 60],
      <double>[55, 32, 50, 22, 50],
      <double>[51, 34, 44, 26, 40],
    ];
    for (final List<double> leg in legs) {
      _mirrored(canvas, (Canvas c, double dir) {
        final Path p = Path()
          ..moveTo(50 + dir * 7, leg[0])
          ..quadraticBezierTo(
            50 - dir * (50 - leg[1]),
            leg[2],
            50 - dir * (50 - leg[3]),
            leg[4],
          );
        c.drawPath(p, stroke);
      });
    }

    // --- Pedipalpos (pinças) -------------------------------------------------
    stroke.strokeWidth = 2.6 * strokeScale;
    _mirrored(canvas, (Canvas c, double dir) {
      final Path arm = Path()
        ..moveTo(50 + dir * 8, 70)
        ..quadraticBezierTo(50 + dir * 20, 74, 50 + dir * 26, 82);
      c.drawPath(arm, stroke);

      // Garra: dois dedos formando um V aberto para fora.
      final Path claw = Path()
        ..moveTo(50 + dir * 22, 80)
        ..quadraticBezierTo(50 + dir * 33, 84, 50 + dir * 31, 93)
        ..quadraticBezierTo(50 + dir * 27, 87, 50 + dir * 21, 85)
        ..close();
      c.drawPath(claw, fill..style = PaintingStyle.fill);

      final Path finger = Path()
        ..moveTo(50 + dir * 30, 91)
        ..quadraticBezierTo(50 + dir * 24, 92, 50 + dir * 21, 88);
      c.drawPath(finger, stroke);
    });

    // --- Prossoma (carapaça) e mesossoma (abdome) ----------------------------
    fill.style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 68), width: 21, height: 16),
      fill,
    );

    const List<List<double>> segments = <List<double>>[
      <double>[61, 18.5, 11],
      <double>[54, 17, 10],
      <double>[47.5, 15, 9],
      <double>[41.5, 13, 8],
    ];
    for (final List<double> s in segments) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(50, s[0]),
            width: s[1],
            height: s[2],
          ),
          const Radius.circular(5),
        ),
        fill,
      );
    }

    // --- Metassoma (cauda) ---------------------------------------------------
    // Cinco anéis de raio decrescente sobre um arco que se curva sobre o dorso.
    const List<List<double>> tail = <List<double>>[
      <double>[49, 34, 4.6],
      <double>[45, 28, 4.1],
      <double>[43.5, 21.5, 3.7],
      <double>[46.5, 15.5, 3.3],
      <double>[52.5, 11.5, 3.0],
    ];
    for (final List<double> t in tail) {
      canvas.drawCircle(Offset(t[0], t[1]), t[2], fill);
    }

    // Télson: vesícula seguida do acúleo (ferrão) voltado para baixo.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(59, 11.5), width: 9, height: 7.4),
      fill,
    );
    final Path sting = Path()
      ..moveTo(62.5, 9.5)
      ..quadraticBezierTo(70, 12, 68.5, 20.5)
      ..quadraticBezierTo(65.5, 15, 61.5, 14.5)
      ..close();
    canvas.drawPath(sting, fill);

    // --- Olhos medianos ------------------------------------------------------
    final Paint eye = Paint()..color = color.withValues(alpha: 0.35);
    canvas.drawCircle(const Offset(47.6, 66), 1.5, eye);
    canvas.drawCircle(const Offset(52.4, 66), 1.5, eye);
  }

  /// Executa [draw] duas vezes: uma para cada lado do eixo vertical.
  void _mirrored(Canvas canvas, void Function(Canvas canvas, double dir) draw) {
    draw(canvas, -1);
    draw(canvas, 1);
  }

  @override
  bool shouldRepaint(_ScorpionPainter old) =>
      old.color != color || old.glow != glow || old.strokeScale != strokeScale;
}

/// Logotipo: marca + nome. Usado no splash, no login e no cabeçalho "Sobre".
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.markSize = 44,
    this.showWordmark = true,
    this.glow = 0,
    this.axis = Axis.horizontal,
  });

  final double markSize;
  final bool showWordmark;
  final double glow;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final Widget mark = ScorpionMark(size: markSize, glow: glow);
    if (!showWordmark) return mark;

    final Widget word = _Wordmark(fontSize: markSize * 0.46);
    return axis == Axis.horizontal
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[mark, SizedBox(width: markSize * 0.28), word],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[mark, SizedBox(height: markSize * 0.34), word],
          );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.fontSize});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    // Tracking largo: leitura de instrumento, não de aplicativo de consumo.
    //
    // O texto vem de AppConfig.appName em vez de um literal — a marca e o
    // nome do produto não podem divergir sem ninguém perceber, que foi
    // exatamente o risco na troca de Telson para Scorpions.
    //
    // O espaçamento é menor que o original porque a palavra passou de 6
    // para 9 letras: mantido o valor antigo, o logotipo estourava a
    // largura em telas de 320dp.
    return Text(
      AppConfig.appName.toUpperCase(),
      style: context.text.display.copyWith(
        fontSize: fontSize,
        letterSpacing: math.max(1.2, fontSize * 0.14),
        fontWeight: FontWeight.w700,
        color: context.colors.textPrimary,
      ),
    );
  }
}
