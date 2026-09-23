import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/feedback_states.dart';
import '../../../data/models/species.dart';
import '../../../core/theme/app_sizing.dart';

/// Painel de relevância médica.
///
/// Regra inviolável do produto: informação médica NUNCA é apresentada como
/// diagnóstico, e todo o bloco carrega um aviso explícito. A cor comunica o
/// grau documentado sem alarmar — terracota para relevância significativa,
/// areia para moderada, neutro para baixa.
class MedicalRelevancePanel extends StatelessWidget {
  const MedicalRelevancePanel({super.key, required this.species});

  final Species species;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final MedicalRelevance relevance = species.medicalRelevance;

    final (Color tint, Color background, DisclaimerTone tone) = switch (
        relevance) {
      MedicalRelevance.significant => (c.error, c.errorSoft, DisclaimerTone.critical),
      MedicalRelevance.moderate => (c.secondary, c.warningSoft, DisclaimerTone.caution),
      MedicalRelevance.low ||
      MedicalRelevance.unknown =>
        (c.textSecondary, c.surfaceSunken, DisclaimerTone.neutral),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: AppSpacing.card,
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadii.brLg,
            border: Border.all(color: tint.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(_icon(relevance), size: AppSizing.iconLg, color: tint),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      relevance.label,
                      style: context.text.h4.copyWith(color: tint),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(species.medicalNotes, style: context.text.bodySmall),
            ],
          ),
        ),
        AppSpacing.gapMd,
        // O aviso é obrigatório e não pode ser removido pela tela.
        const DisclaimerBanner(
          message: AppStrings.medicalDisclaimer,
          tone: DisclaimerTone.critical,
          icon: Icons.emergency_outlined,
        ),
      ],
    );
  }

  IconData _icon(MedicalRelevance relevance) => switch (relevance) {
        MedicalRelevance.significant => Icons.warning_amber_rounded,
        MedicalRelevance.moderate => Icons.info_outline_rounded,
        MedicalRelevance.low => Icons.check_circle_outline_rounded,
        MedicalRelevance.unknown => Icons.help_outline_rounded,
      };
}
