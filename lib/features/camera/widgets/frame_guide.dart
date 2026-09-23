import 'package:flutter/material.dart';

/// Moldura de enquadramento: quatro cantos em L sobre a área de captura.
///
/// É a instrução visual mais importante da câmera. Ela comunica, sem texto,
/// onde o animal precisa estar — e na Fase 5 essa mesma região define o recorte
/// enviado ao modelo, então a moldura não é decorativa: é contrato.
class FrameGuide extends StatelessWidget {
  const FrameGuide({
    super.key,
    required this.color,
    this.child,
    this.cornerLength = 34,
    this.thickness = 3,
    this.radius = 18,
    this.opacity = 1,
  });

  final Color color;
  final Widget? child;
  final double cornerLength;
  final double thickness;
  final double radius;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FrameGuidePainter(
        color: color.withValues(alpha: opacity),
        cornerLength: cornerLength,
        thickness: thickness,
        radius: radius,
      ),
      child: child,
    );
  }
}

class _FrameGuidePainter extends CustomPainter {
  _FrameGuidePainter({
    required this.color,
    required this.cornerLength,
    required this.thickness,
    required this.radius,
  });

  final Color color;
  final double cornerLength;
  final double thickness;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final double w = size.width;
    final double h = size.height;
    final double len = cornerLength.clamp(0, (w < h ? w : h) / 2 - radius);

    void corner(double x, double y, double dx, double dy) {
      final Path path = Path()
        ..moveTo(x + dx * (radius + len), y)
        ..lineTo(x + dx * radius, y)
        ..arcToPoint(
          Offset(x, y + dy * radius),
          radius: Radius.circular(radius),
          clockwise: dx * dy < 0,
        )
        ..lineTo(x, y + dy * (radius + len));
      canvas.drawPath(path, paint);
    }

    corner(0, 0, 1, 1);
    corner(w, 0, -1, 1);
    corner(w, h, -1, -1);
    corner(0, h, 1, -1);
  }

  @override
  bool shouldRepaint(_FrameGuidePainter old) =>
      old.color != color ||
      old.cornerLength != cornerLength ||
      old.thickness != thickness ||
      old.radius != radius;
}
