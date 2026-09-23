import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// Feedback tátil de pressão.
///
/// Envolve qualquer conteúdo e aplica uma leve redução de escala enquanto o
/// dedo está sobre ele. É a microinteração de base do app: todo elemento
/// clicável passa por aqui, o que garante que o toque tenha sempre a mesma
/// sensação.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.borderRadius,
    this.semanticLabel,
    this.enableFeedback = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Escala aplicada enquanto pressionado.
  final double scale;

  /// Usado apenas para recortar o brilho de toque quando houver.
  final BorderRadius? borderRadius;

  final String? semanticLabel;
  final bool enableFeedback;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _setPressed(bool value) {
    if (!_enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = AnimatedScale(
      scale: _pressed ? widget.scale : 1,
      duration: AppMotion.instant,
      curve: AppMotion.standard,
      child: AnimatedOpacity(
        opacity: _pressed ? 0.88 : 1,
        duration: AppMotion.instant,
        child: widget.child,
      ),
    );

    return Semantics(
      button: _enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: content,
      ),
    );
  }
}
