import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_sizing.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/pressable.dart';

/// Faixa inferior da câmera: galeria à esquerda, botão de captura ao centro.
///
/// # Sobre as cores
/// Tudo aqui usa `onMedia` / `onMediaDim`, não `Colors.white`. A distinção
/// importa: sobre uma fotografia o contraste **não** segue o tema claro/escuro,
/// é sempre claro — e isso é uma regra do design system, não um literal solto
/// (era a origem de 13 dos 14 `Colors.white` encontrados na auditoria).
class CaptureControls extends StatelessWidget {
  const CaptureControls({
    super.key,
    required this.onShoot,
    required this.onGallery,
    this.busy = false,
  });

  final VoidCallback? onShoot;
  final VoidCallback onGallery;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.lg,
        AppSpacing.xxl,
        AppSpacing.xxl,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _GalleryButton(onTap: onGallery),
            ),
          ),
          _ShutterButton(onTap: onShoot, busy: busy),
          // Espaço-espelho para manter o disparo centralizado.
          const Expanded(child: SizedBox.shrink()),
        ],
      ),
    );
  }
}

/// Botão de disparo.
///
/// Anel externo fixo e miolo que encolhe ao pressionar: é o gesto físico de uma
/// câmera de verdade, e o maior alvo tocável da tela.
class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.onTap, required this.busy});

  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final bool enabled = onTap != null && !busy;

    return Pressable(
      onTap: enabled ? onTap : null,
      scale: 0.9,
      semanticLabel: busy ? 'Capturando' : 'Capturar foto',
      child: SizedBox(
        width: AppSizing.shutter,
        height: AppSizing.shutter,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // Anel externo.
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: enabled
                      ? c.onMedia
                      : c.onMedia.withValues(alpha: 0.35),
                  width: 3.5,
                ),
              ),
              child: const SizedBox.expand(),
            ),
            // Miolo.
            AnimatedContainer(
              duration: AppMotion.fast,
              curve: AppMotion.standard,
              width: busy ? AppSizing.shutterInner * 0.72 : AppSizing.shutterInner,
              height:
                  busy ? AppSizing.shutterInner * 0.72 : AppSizing.shutterInner,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled
                    ? c.primary
                    : c.onMedia.withValues(alpha: 0.22),
              ),
            ),
            if (busy)
              SizedBox(
                width: AppSizing.shutterInner,
                height: AppSizing.shutterInner,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(c.onMedia),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GalleryButton extends StatelessWidget {
  const _GalleryButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return Pressable(
      onTap: onTap,
      scale: 0.92,
      semanticLabel: 'Escolher foto da galeria',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: AppSizing.avatarSmall + AppSpacing.xl,
            height: AppSizing.avatarSmall + AppSpacing.xl,
            decoration: BoxDecoration(
              color: c.scrim,
              borderRadius: AppRadii.brMd,
              border: Border.all(color: c.onMedia.withValues(alpha: 0.24)),
            ),
            child: Icon(
              Icons.photo_library_outlined,
              size: AppSizing.iconLg,
              color: c.onMedia,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            AppStrings.cameraGallery,
            style: context.text.overlineSmall.copyWith(color: c.onMediaDim),
          ),
        ],
      ),
    );
  }
}
