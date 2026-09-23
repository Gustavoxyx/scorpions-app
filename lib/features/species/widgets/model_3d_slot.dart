import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_sizing.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/scorpion_mark.dart';
import '../../../data/models/species.dart';

/// Espaço reservado ao visualizador tridimensional (brief §20 e §24).
///
/// # Por que ele aparece desativado em vez de não aparecer
/// Esconder a funcionalidade até ela existir faria a tela ser redesenhada
/// quando o 3D chegasse — e o brief §20 pede exatamente o contrário. Mostrá-lo
/// inativo, com o motivo escrito, também é mais honesto com o usuário do que
/// um botão que promete algo que ainda não funciona.
///
/// # O que muda na Fase 7
/// `Species.model3D` deixa de ser nulo e [onExplore] recebe a rota do
/// visualizador. O layout, o espaço ocupado e a posição na tela permanecem
/// idênticos — nenhuma outra tela precisa mudar.
class Model3DSlot extends StatelessWidget {
  const Model3DSlot({
    super.key,
    required this.species,
    this.onExplore,
    this.compact = false,
  });

  final Species species;

  /// Chamado quando houver visualizador. Ignorado enquanto não houver modelo.
  final VoidCallback? onExplore;

  /// Versão reduzida, usada dentro da tela de resultado.
  final bool compact;

  bool get _available => species.has3DModel && onExplore != null;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return Semantics(
      button: _available,
      enabled: _available,
      label: _available
          ? 'Explorar ${species.scientificName} em três dimensões'
          : 'Exploração em 3D indisponível para esta espécie',
      child: Pressable(
        onTap: _available ? onExplore : null,
        child: Container(
          padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl),
          decoration: BoxDecoration(
            color: _available ? c.surface : c.surfaceVariant,
            borderRadius: AppRadii.brLg,
            border: Border.all(
              color: _available ? c.primary.withValues(alpha: 0.35) : c.border,
            ),
          ),
          child: Row(
            children: <Widget>[
              _Thumbnail(available: _available, compact: compact),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Explorar em 3D',
                      style: context.text.h4.copyWith(
                        color: _available ? c.textPrimary : c.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      _available
                          ? 'Gire, aproxime e toque nas partes do corpo.'
                          : 'Modelo tridimensional ainda não disponível '
                              'para esta espécie.',
                      style: context.text.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                _available
                    ? Icons.threed_rotation_rounded
                    : Icons.lock_clock_outlined,
                size: AppSizing.iconMd,
                color: _available ? c.primary : c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Miniatura do modelo. Enquanto não há arquivo 3D, mostra a silhueta vetorial
/// sobre uma retícula — a mesma linguagem das placas de espécie.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.available, required this.compact});

  final bool available;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final double side =
        compact ? AppSizing.iconTileMedium : AppSizing.thumbSmall;

    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: AppRadii.brSm,
        border: Border.all(color: c.border),
      ),
      child: Center(
        child: ScorpionMark(
          size: side * 0.56,
          color: (available ? c.primary : c.textTertiary)
              .withValues(alpha: available ? 0.9 : 0.45),
        ),
      ),
    );
  }
}
