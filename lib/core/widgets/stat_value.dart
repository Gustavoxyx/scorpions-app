import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_sizing.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Número grande com rótulo — a "estatística" do produto.
///
/// # Por que existe
/// A auditoria da Fase 2 encontrou o mesmo padrão desenhado três vezes em
/// tamanhos diferentes: 26 no catálogo, 24 no histórico e 30 no perfil. Não
/// havia razão para a diferença — era só cada tela escolhendo um número. Com um
/// componente, a contagem de espécies do catálogo e a de identificações do
/// perfil passam a ter exatamente o mesmo peso visual.
///
/// O valor usa algarismos tabulares: quando o número muda (ou anima), os
/// dígitos não "dançam" de largura.
class StatValue extends StatelessWidget {
  const StatValue({
    super.key,
    required this.value,
    required this.label,
    this.tint,
    this.alignment = CrossAxisAlignment.center,
    this.compact = false,
  });

  final String value;
  final String label;

  /// Cor do número. Padrão: cor de texto principal.
  final Color? tint;

  final CrossAxisAlignment alignment;

  /// Versão reduzida, para dentro de cabeçalhos.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final bool centered = alignment == CrossAxisAlignment.center;

    return Column(
      crossAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          maxLines: 1,
          style: context.text.display.copyWith(
            fontSize: compact ? 24 : 28,
            height: 1,
            color: tint ?? c.textPrimary,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: context.text.overlineSmall.copyWith(color: c.textTertiary),
        ),
      ],
    );
  }
}

/// Faixa de estatísticas separadas por filetes.
///
/// Usada no resumo do histórico e no perfil. Distribui as colunas por igual e
/// mantém o mesmo filete divisório dos dois lados do app.
class StatStrip extends StatelessWidget {
  const StatStrip({
    super.key,
    required this.stats,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.lg,
    ),
    this.bordered = true,
  });

  final List<StatValue> stats;
  final EdgeInsetsGeometry padding;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return Container(
      padding: padding,
      decoration: bordered
          ? BoxDecoration(
              color: c.surface,
              borderRadius: AppRadii.brLg,
              border: Border.all(color: c.border),
            )
          : null,
      child: Row(
        children: <Widget>[
          for (int i = 0; i < stats.length; i++) ...<Widget>[
            if (i > 0)
              Container(
                width: AppSizing.hairline,
                height: 32,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                color: c.border,
              ),
            Expanded(child: stats[i]),
          ],
        ],
      ),
    );
  }
}
