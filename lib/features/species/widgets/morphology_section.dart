import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/pressable.dart';
import '../../../data/models/species.dart';

/// Seção de morfologia.
///
/// Cada estrutura (pedipalpos, cauda, ferrão, pinças…) é um item expansível.
/// Na Fase 7 esta lista alimentará um diagrama interativo onde tocar a parte
/// destaca a região no desenho; por ora, a interação é a expansão do texto —
/// já com o mesmo modelo de dados, para que a evolução não exija reescrita.
class MorphologySection extends StatefulWidget {
  const MorphologySection({super.key, required this.features});

  final List<MorphologyFeature> features;

  @override
  State<MorphologySection> createState() => _MorphologySectionState();
}

class _MorphologySectionState extends State<MorphologySection> {
  int _expanded = 0;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppRadii.brLg,
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < widget.features.length; i++) ...<Widget>[
            if (i > 0) Divider(height: 1, color: c.border),
            _FeatureTile(
              index: i + 1,
              feature: widget.features[i],
              expanded: _expanded == i,
              onTap: () => setState(() => _expanded = _expanded == i ? -1 : i),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.index,
    required this.feature,
    required this.expanded,
    required this.onTap,
  });

  final int index;
  final MorphologyFeature feature;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.base,
        color: expanded ? c.surfaceVariant : Colors.transparent,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: expanded ? c.primary : c.surfaceSunken,
                    borderRadius: AppRadii.brXs,
                  ),
                  child: Text(
                    '$index',
                    style: context.text.labelSmall.copyWith(
                      color: expanded ? c.onPrimary : c.textTertiary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(feature.name, style: context.text.h4),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: AppMotion.base,
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      size: 20, color: c.textTertiary),
                ),
              ],
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.md,
                  left: 38,
                ),
                child: Text(feature.description, style: context.text.bodySmall),
              ),
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: AppMotion.base,
              sizeCurve: AppMotion.emphasized,
            ),
          ],
        ),
      ),
    );
  }
}
