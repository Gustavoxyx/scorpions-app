import 'package:flutter/material.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/reveal.dart';
import '../../core/theme/app_sizing.dart';

/// Guia de captura.
///
/// Conteúdo educativo que melhora a qualidade das fotos — e, portanto, a
/// qualidade das identificações quando o modelo real chegar. Cada dica é
/// acionável e específica, sem jargão.
class PhotoTipsPage extends StatelessWidget {
  const PhotoTipsPage({super.key});

  static const List<(IconData, String, String)> _tips =
      <(IconData, String, String)>[
    (
      Icons.wb_sunny_outlined,
      'Boa iluminação',
      'Prefira luz natural indireta. Evite flash direto, que estoura o brilho '
          'do exoesqueleto e apaga os detalhes.'
    ),
    (
      Icons.center_focus_strong_outlined,
      'Corpo inteiro no quadro',
      'Enquadre o animal por completo — cauda, pinças e pernas. As proporções '
          'entre essas partes são o que distingue as espécies.'
    ),
    (
      Icons.filter_center_focus_rounded,
      'Foco nítido',
      'Toque na tela sobre o animal para focar. Uma foto tremida ou desfocada '
          'costuma resultar em "não identificado".'
    ),
    (
      Icons.landscape_outlined,
      'Fundo limpo e distância segura',
      'Um fundo neutro ajuda a recortar o animal. Mantenha distância: nunca '
          'toque no escorpião para fotografar.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: AppStrings.photoTipsTitle,
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: Reveal.stagger(<Widget>[
          Text(AppStrings.photoTipsSubtitle, style: context.text.body),
          AppSpacing.gapXl,
          for (int i = 0; i < _tips.length; i++) ...<Widget>[
            _TipCard(
              index: i + 1,
              icon: _tips[i].$1,
              title: _tips[i].$2,
              body: _tips[i].$3,
            ),
            if (i < _tips.length - 1) AppSpacing.gapMd,
          ],
        ]),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({
    required this.index,
    required this.icon,
    required this.title,
    required this.body,
  });

  final int index;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Container(
      padding: AppSpacing.card,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadii.brLg,
        border: Border.all(color: c.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: c.primarySoft,
              borderRadius: AppRadii.brSm,
            ),
            child: Icon(icon, size: AppSizing.iconLg, color: c.primary),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(title, style: context.text.h4),
                const SizedBox(height: AppSpacing.xs),
                Text(body, style: context.text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
