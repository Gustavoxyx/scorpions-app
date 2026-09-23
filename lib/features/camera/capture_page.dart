import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router/app_routes.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/feedback_states.dart';
import '../../data/models/captured_image.dart';
import '../../data/services/camera_service.dart';
import '../../data/services/gallery_service.dart';
import '../../state/identification_controller.dart';
import 'camera_session.dart';
import 'widgets/capture_controls.dart';
import 'widgets/frame_guide.dart';
import '../../core/theme/app_sizing.dart';

/// Tela de captura.
///
/// Três caminhos levam à mesma saída — câmera real, galeria e captura simulada
/// —, e todos produzem um [CapturedImage]. Por isso o restante do fluxo
/// (confirmação, análise, resultado) não sabe de onde a imagem veio.
///
/// Permissões: não pedimos nada na abertura do aplicativo. O pedido acontece
/// aqui, no momento em que a câmera é realmente necessária, e a negativa tem
/// uma tela própria explicando o motivo do pedido.
class CapturePage extends StatefulWidget {
  const CapturePage({super.key});

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  late final CameraSession _session;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _session = CameraSession(context.read<CameraService>());
    WidgetsBinding.instance.addObserver(_session);
    _session.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_session);
    _session.dispose();
    super.dispose();
  }

  Future<void> _handleImage(CapturedImage? image) async {
    if (image == null || !mounted) return;
    context.read<IdentificationController>().stageImage(image);
    context.push(AppRoutes.confirmPhoto);
  }

  Future<void> _shoot() async {
    if (_busy) return;
    setState(() => _busy = true);
    final CapturedImage? image = await _session.capture();
    if (mounted) setState(() => _busy = false);
    await _handleImage(image);
  }

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    setState(() => _busy = true);
    CapturedImage? image;
    try {
      image = await context.read<GalleryService>().pick();
    } catch (_) {
      // Plataforma sem seletor de arquivos: seguimos com a imagem simulada
      // para que o fluxo permaneça navegável.
      image = CapturedImage.simulated();
    }
    if (mounted) setState(() => _busy = false);
    await _handleImage(image);
  }

  Future<void> _simulate() => _handleImage(CapturedImage.simulated());

  @override
  Widget build(BuildContext context) {
    // O visor é sempre escuro, mesmo no tema claro: é uma superfície de mídia,
    // não uma superfície da interface.
    return Scaffold(
      backgroundColor: const Color(0xFF07100C),
      body: ListenableBuilder(
        listenable: _session,
        builder: (BuildContext context, _) {
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              _viewfinder(context),
              // Véu escuro nas bordas: destaca a área de enquadramento.
              const _EdgeVignette(),
              SafeArea(
                child: Column(
                  children: <Widget>[
                    _TopBar(
                      onClose: () => context.pop(),
                      onSwitch: _session.canSwitchCamera
                          ? _session.switchCamera
                          : null,
                      onTips: () => context.push(AppRoutes.photoTips),
                    ),
                    Expanded(child: _overlay(context)),
                    CaptureControls(
                      onShoot: _session.isReady ? _shoot : null,
                      onGallery: _pickFromGallery,
                      busy: _busy ||
                          _session.status == CameraSessionStatus.capturing,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Área de pré-visualização — ou o substituto quando não há câmera.
  Widget _viewfinder(BuildContext context) {
    final CameraController? controller = _session.controller;
    if (_session.isReady && controller != null) {
      // `CameraPreview` respeita a proporção do sensor; cobrimos a tela para
      // não deixar faixas pretas laterais.
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.previewSize?.height ?? 1,
          height: controller.value.previewSize?.width ?? 1,
          child: CameraPreview(controller),
        ),
      );
    }
    return ColoredBox(color: context.colors.surfaceSunken);
  }

  /// Conteúdo sobreposto: moldura, instrução ou estado alternativo.
  Widget _overlay(BuildContext context) {
    return switch (_session.status) {
      CameraSessionStatus.ready ||
      CameraSessionStatus.capturing =>
        _FramingOverlay(active: _session.status == CameraSessionStatus.ready),
      CameraSessionStatus.initializing => const Center(
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      CameraSessionStatus.permissionDenied => _PermissionState(
          onRetry: _session.start,
          onGallery: _pickFromGallery,
        ),
      CameraSessionStatus.unavailable => _UnavailableState(
          onGallery: _pickFromGallery,
          onSimulate: _simulate,
        ),
      CameraSessionStatus.error => ErrorState(
          title: 'Falha na câmera',
          message: _session.errorMessage ??
              'Não foi possível iniciar a captura neste aparelho.',
          onRetry: _session.start,
        ),
    };
  }
}

/// Moldura + instrução.
class _FramingOverlay extends StatelessWidget {
  const _FramingOverlay({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      child: Column(
        children: <Widget>[
          const Spacer(),
          AspectRatio(
            aspectRatio: 1,
            child: AnimatedOpacity(
              opacity: active ? 1 : 0.4,
              duration: AppMotion.base,
              child: FrameGuide(color: c.primary),
            ),
          ),
          AppSpacing.gapXl,
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: c.scrim,
              borderRadius: AppRadii.brMd,
            ),
            child: Column(
              children: <Widget>[
                Text(
                  AppStrings.cameraGuide,
                  textAlign: TextAlign.center,
                  style: context.text.h4.copyWith(color: c.onMedia),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  AppStrings.cameraHint,
                  textAlign: TextAlign.center,
                  style: context.text.caption.copyWith(color: c.onMediaDim),
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onClose, this.onSwitch, this.onTips});

  final VoidCallback onClose;
  final VoidCallback? onSwitch;

  /// Atalho para o guia de fotografia. Fica aqui — e não só na Home — porque é
  /// exatamente no momento de enquadrar que a dúvida "como tiro uma boa foto?"
  /// aparece (brief §15).
  final VoidCallback? onTips;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: <Widget>[
          AppIconButton(
            icon: Icons.close_rounded,
            tooltip: AppStrings.close,
            onPressed: onClose,
            background: c.scrim,
            foreground: c.onMedia,
          ),
          const Spacer(),
          if (onTips != null) ...<Widget>[
            AppIconButton(
              icon: Icons.lightbulb_outline_rounded,
              tooltip: 'Dicas de fotografia',
              onPressed: onTips,
              background: c.scrim,
              foreground: c.onMedia,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          if (onSwitch != null)
            AppIconButton(
              icon: Icons.cameraswitch_outlined,
              tooltip: 'Trocar câmera',
              onPressed: onSwitch,
              background: c.scrim,
              foreground: c.onMedia,
            ),
        ],
      ),
    );
  }
}

class _PermissionState extends StatelessWidget {
  const _PermissionState({required this.onRetry, required this.onGallery});

  final VoidCallback onRetry;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return _AlternativePanel(
      icon: Icons.no_photography_outlined,
      title: AppStrings.cameraPermissionTitle,
      message: AppStrings.cameraPermissionBody,
      primaryLabel: AppStrings.cameraPermissionAction,
      onPrimary: onRetry,
      secondaryLabel: AppStrings.cameraGallery,
      onSecondary: onGallery,
    );
  }
}

class _UnavailableState extends StatelessWidget {
  const _UnavailableState({required this.onGallery, required this.onSimulate});

  final VoidCallback onGallery;
  final VoidCallback onSimulate;

  @override
  Widget build(BuildContext context) {
    return _AlternativePanel(
      icon: Icons.videocam_off_outlined,
      title: AppStrings.cameraUnavailableTitle,
      message: AppStrings.cameraUnavailableBody,
      primaryLabel: AppStrings.cameraGallery,
      onPrimary: onGallery,
      secondaryLabel: 'Usar imagem simulada',
      onSecondary: onSimulate,
    );
  }
}

/// Painel usado quando a câmera não pode ser aberta.
class _AlternativePanel extends StatelessWidget {
  const _AlternativePanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: AppRadii.brLg,
            border: Border.all(color: c.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: AppSizing.iconHero, color: c.textTertiary),
              AppSpacing.gapLg,
              Text(title, textAlign: TextAlign.center, style: context.text.h3),
              AppSpacing.gapSm,
              Text(
                message,
                textAlign: TextAlign.center,
                style: context.text.bodySmall,
              ),
              AppSpacing.gapXl,
              AppButton(label: primaryLabel, onPressed: onPrimary),
              AppSpacing.gapSm,
              AppButton(
                label: secondaryLabel,
                variant: AppButtonVariant.secondary,
                onPressed: onSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Escurecimento radial das bordas do visor.
class _EdgeVignette extends StatelessWidget {
  const _EdgeVignette();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 1.1,
            colors: <Color>[
              Colors.transparent,
              const Color(0xFF000000).withValues(alpha: 0.55),
            ],
            stops: const <double>[0.55, 1],
          ),
        ),
      ),
    );
  }
}
