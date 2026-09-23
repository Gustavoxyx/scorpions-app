import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

/// Efeito de varredura sobre a foto em análise.
///
/// Não é uma barra de progresso: é uma linha de luz que percorre a imagem, com
/// um reticulado que "acende" à sua passagem — a metáfora de um scanner
/// examinando o espécime. Comunica trabalho ativo, que era o pedido explícito
/// para esta tela. Quando o modelo real chegar, a animação passa a acompanhar o
/// progresso verdadeiro de inferência.
class ScannerAnimation extends StatefulWidget {
  const ScannerAnimation({super.key, required this.child});

  final Widget child;

  @override
  State<ScannerAnimation> createState() => _ScannerAnimationState();
}

class _ScannerAnimationState extends State<ScannerAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          widget.child,
          // Escurece a foto para que a luz da varredura tenha contraste.
          ColoredBox(color: c.background.withValues(alpha: 0.35)),
          AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, _) => CustomPaint(
              painter: _ScannerPainter(
                progress: _controller.value,
                color: c.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerPainter extends CustomPainter {
  _ScannerPainter({required this.progress, required this.color});

  /// 0..1, percorre de cima a baixo e volta.
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Reticulado de fundo.
    final Paint grid = Paint()
      ..color = color.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    const double step = 26;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // Movimento de vai-e-vem suavizado.
    final double eased = (math.sin((progress * 2 - 0.5) * math.pi) + 1) / 2;
    final double y = eased * size.height;

    // Rastro luminoso acima da linha.
    final Rect trail = Rect.fromLTWH(0, y - 60, size.width, 60);
    canvas.drawRect(
      trail,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            color.withValues(alpha: 0),
            color.withValues(alpha: 0.22),
          ],
        ).createShader(trail),
    );

    // Linha de varredura.
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // Pontos de amostragem que acendem perto da linha.
    final Paint node = Paint()..color = color;
    final math.Random rng = math.Random(7);
    for (int i = 0; i < 14; i++) {
      final double px = rng.nextDouble() * size.width;
      final double py = rng.nextDouble() * size.height;
      final double distance = (py - y).abs();
      if (distance < 40) {
        node.color = color.withValues(alpha: (1 - distance / 40) * 0.9);
        canvas.drawCircle(Offset(px, py), 2.4, node);
      }
    }
  }

  @override
  bool shouldRepaint(_ScannerPainter old) => old.progress != progress;
}
