import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_sizing.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/scorpion_mark.dart';

/// Cartão principal da Home.
///
/// # Por que ele domina a tela
/// Quem abre este aplicativo tem uma dúvida urgente — "o que é esse bicho?" — e
/// a resposta precisa estar a um toque. Todo o resto da Home é deliberadamente
/// mais leve do que este cartão.
///
/// # Por que o cartão muda entre os temas
/// No tema claro ele é uma **superfície verde cheia** sobre papel off-white: o
/// contraste de área faz o olho pousar nele antes de qualquer outra coisa. No
/// tema escuro isso se inverteria — um bloco de verde claro sobre fundo quase
/// preto ofusca — então ele vira superfície elevada com borda e botão verdes.
/// Duas execuções, uma única intenção: ser o elemento mais forte da tela.
///
/// # Por que não há animação em laço
/// A versão da Fase 1 pulsava para sempre (`repeat(reverse: true)`), repintando
/// o cartão enquanto a Home estivesse aberta. Não ajudava a entender nada e
/// custava bateria — reprovada no teste do §31. A entrada agora é única.
class IdentifyHeroCard extends StatelessWidget {
  const IdentifyHeroCard({super.key, required this.onIdentify});

  final VoidCallback onIdentify;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final bool filled = !c.isDark;

    final Color surface = filled ? c.primary : c.surfaceVariant;
    final Color onSurface = filled ? c.onPrimary : c.textPrimary;
    final Color onSurfaceDim =
        filled ? c.onPrimary.withValues(alpha: 0.78) : c.textSecondary;

    return Semantics(
      container: true,
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: AppRadii.brXl,
          border: filled
              ? null
              : Border.all(color: c.primary.withValues(alpha: 0.30)),
          boxShadow: AppShadows.level2(c.brightness),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: <Widget>[
            // Marca sangrando no canto: textura de fundo, não ilustração.
            // Fica atrás do texto e nunca disputa atenção com ele.
            Positioned(
              right: -38,
              top: -30,
              child: ScorpionMark(
                size: 200,
                color: (filled ? c.onPrimary : c.primary)
                    .withValues(alpha: filled ? 0.10 : 0.07),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Eyebrow(filled: filled),
                  AppSpacing.gapLg,
                  Text(
                    AppStrings.homeCardTitle,
                    style: context.text.display.copyWith(
                      color: onSurface,
                      fontSize: context.isCompact ? 27 : 32,
                    ),
                  ),
                  AppSpacing.gapSm,
                  Text(
                    AppStrings.homeCardBody,
                    style: context.text.body.copyWith(color: onSurfaceDim),
                  ),
                  AppSpacing.gapXl,
                  _IdentifyButton(filled: filled, onPressed: onIdentify),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Etiqueta acima do título. Diz o que o app faz antes de dizer o que fazer.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.filled});

  final bool filled;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    if (!filled) {
      return const AppBadge(
        label: 'IDENTIFICAÇÃO POR IMAGEM',
        tone: AppBadgeTone.primary,
        icon: Icons.center_focus_strong_rounded,
        dense: true,
      );
    }
    // Sobre a superfície verde cheia, a etiqueta usa o inverso do primário.
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs + 2,
      ),
      decoration: BoxDecoration(
        color: c.onPrimary.withValues(alpha: 0.14),
        borderRadius: AppRadii.brPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.center_focus_strong_rounded,
            size: AppSizing.iconXs,
            color: c.onPrimary,
          ),
          const SizedBox(width: AppSpacing.xs + 1),
          // `Flexible` não é detalhe: com a fonte ampliada por acessibilidade,
          // ou numa tela de 320dp, este rótulo em caixa alta é o texto mais
          // largo do cartão. Sem isto ele estoura a linha.
          Flexible(
            child: Text(
              'IDENTIFICAÇÃO POR IMAGEM',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.overlineSmall.copyWith(color: c.onPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Botão de ação principal do aplicativo.
///
/// Sobre a superfície verde ele é invertido (claro sobre verde); no tema escuro
/// volta a ser o botão primário padrão. Em ambos os casos é o alvo mais óbvio
/// da tela.
class _IdentifyButton extends StatelessWidget {
  const _IdentifyButton({required this.filled, required this.onPressed});

  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    if (!filled) {
      return AppButton(
        label: AppStrings.identifyCta,
        icon: Icons.camera_alt_rounded,
        onPressed: onPressed,
      );
    }

    return Pressable(
      onTap: onPressed,
      semanticLabel: AppStrings.identifyCta,
      child: Container(
        height: AppSizing.buttonLarge,
        width: double.infinity,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: AppRadii.brMd,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.camera_alt_rounded,
              size: AppSizing.iconLg,
              color: c.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                AppStrings.identifyCta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.label.copyWith(color: c.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cartão de atalho da Home.
///
/// Deliberadamente discreto: ícone pequeno, sem cor de preenchimento, altura
/// baixa. Ele existe para levar a algum lugar, não para competir com o cartão
/// principal (brief §11).
class ShortcutCard extends StatelessWidget {
  const ShortcutCard({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.badge,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// Contador opcional — por exemplo, quantas identificações há no histórico.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: AppRadii.brLg,
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: AppSizing.iconTileSmall,
                  height: AppSizing.iconTileSmall,
                  decoration: BoxDecoration(
                    color: c.surfaceSunken,
                    borderRadius: AppRadii.brSm,
                  ),
                  child: Icon(icon, size: AppSizing.iconMd, color: c.primary),
                ),
                const Spacer(),
                if (badge != null)
                  Text(
                    badge!,
                    style: context.text.monoSmall.copyWith(
                      color: c.textTertiary,
                    ),
                  ),
              ],
            ),
            AppSpacing.gapMd,
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.h4,
            ),
          ],
        ),
      ),
    );
  }
}
