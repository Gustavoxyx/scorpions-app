import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/confidence_level.dart';
import '../../core/utils/formatters.dart';
import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Aparência de cada faixa de confiança.
///
/// # Onde moram as cores
/// Não aqui. As cores vêm de `AppColors.confidenceHigh/Medium/Low/None`, no
/// tema — esta extensão apenas as escolhe. A diferença importa: a faixa de
/// confiança é uma **regra de produto**, e o selo, o medidor, o cartão de
/// histórico e a ficha da espécie precisam pintar "alta confiança" com
/// exatamente a mesma cor nos dois temas.
///
/// # Por que também há um ícone
/// Acessibilidade: informação não pode depender só de cor (§34). O ícone e o
/// rótulo textual carregam o mesmo significado para quem não distingue as
/// matizes.
extension ConfidencePalette on ConfidenceLevel {
  Color color(AppColors c) => switch (this) {
        ConfidenceLevel.high => c.confidenceHigh,
        ConfidenceLevel.medium => c.confidenceMedium,
        ConfidenceLevel.low => c.confidenceLow,
        ConfidenceLevel.unidentified => c.confidenceNone,
      };

  Color soft(AppColors c) => switch (this) {
        ConfidenceLevel.high => c.confidenceHighSoft,
        ConfidenceLevel.medium => c.confidenceMediumSoft,
        ConfidenceLevel.low => c.confidenceLowSoft,
        ConfidenceLevel.unidentified => c.confidenceNoneSoft,
      };

  IconData get icon => switch (this) {
        ConfidenceLevel.high => Icons.verified_outlined,
        ConfidenceLevel.medium => Icons.help_outline,
        ConfidenceLevel.low => Icons.priority_high_rounded,
        ConfidenceLevel.unidentified => Icons.block_outlined,
      };
}

/// Selo compacto de confiança. Usado em listas e cabeçalhos.
class ConfidenceBadge extends StatelessWidget {
  const ConfidenceBadge({
    super.key,
    required this.level,
    this.score,
    this.compact = false,
  });

  final ConfidenceLevel level;

  /// Quando informado, o valor numérico aparece ao lado do rótulo.
  final double? score;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final Color tint = level.color(c);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : AppSpacing.md,
        vertical: compact ? AppSpacing.xs : AppSpacing.sm - 1,
      ),
      decoration: BoxDecoration(
        color: level.soft(c),
        borderRadius: AppRadii.brPill,
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(level.icon, size: compact ? 12 : 14, color: tint),
          const SizedBox(width: AppSpacing.xs + 2),
          Text(
            compact ? level.shortLabel : level.label,
            style: (compact ? context.text.labelSmall : context.text.labelSmall)
                .copyWith(color: tint),
          ),
          if (score != null) ...<Widget>[
            const SizedBox(width: AppSpacing.sm - 2),
            Text(
              Formatters.percent(score!),
              style: context.text.mono.copyWith(
                color: tint,
                fontSize: compact ? 11 : 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Medidor em arco. É o elemento gráfico do resultado: comunica magnitude sem
/// virar uma barra de progresso genérica.
class ConfidenceMeter extends StatelessWidget {
  const ConfidenceMeter({
    super.key,
    required this.score,
    required this.level,
    this.size = 132,
    this.animationValue = 1,
  });

  final double score;
  final ConfidenceLevel level;
  final double size;

  /// 0 a 1 — permite animar o preenchimento na entrada da tela.
  final double animationValue;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final Color tint = level.color(c);

    return SizedBox(
      width: size,
      height: size * 0.62,
      child: CustomPaint(
        painter: _MeterPainter(
          value: score * animationValue,
          tint: tint,
          track: c.surfaceSunken,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(height: size * 0.12),
              Text(
                Formatters.percent(score * animationValue),
                style: context.text.display.copyWith(
                  fontSize: size * 0.24,
                  color: tint,
                  height: 1,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                level.shortLabel,
                style: context.text.overline.copyWith(color: c.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  _MeterPainter({
    required this.value,
    required this.tint,
    required this.track,
  });

  final double value;
  final Color tint;
  final Color track;

  /// Arco de 200 graus, aberto para baixo.
  static const double _start = math.pi * 0.888;
  static const double _sweep = math.pi * 1.224;

  @override
  void paint(Canvas canvas, Size size) {
    final double stroke = size.width * 0.062;
    final Rect rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      (size.width - stroke),
    );

    final Paint base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, _start, _sweep, false, base);

    if (value <= 0) return;

    final Paint fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: _start,
        endAngle: _start + _sweep,
        colors: <Color>[tint.withValues(alpha: 0.45), tint],
        transform: const GradientRotation(_start),
      ).createShader(rect);
    canvas.drawArc(rect, _start, _sweep * value.clamp(0.0, 1.0), false, fill);

    // Marcas dos limiares do produto (65% e 85%), para que o número tenha
    // referência visual em vez de flutuar sozinho.
    final Paint tick = Paint()
      ..color = track
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final double t in <double>[0.65, 0.85]) {
      final double angle = _start + _sweep * t;
      final Offset center = rect.center;
      final double outer = rect.width / 2 + stroke * 0.1;
      final double inner = rect.width / 2 - stroke * 0.42;
      canvas.drawLine(
        center + Offset(math.cos(angle) * inner, math.sin(angle) * inner),
        center + Offset(math.cos(angle) * outer, math.sin(angle) * outer),
        tick,
      );
    }
  }

  @override
  bool shouldRepaint(_MeterPainter old) =>
      old.value != value || old.tint != tint || old.track != track;
}
