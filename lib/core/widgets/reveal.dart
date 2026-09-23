import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// Entrada suave de um elemento: opacidade + pequeno deslocamento vertical.
///
/// É o bloco de construção da "sensação de descoberta" pedida para a tela de
/// resultado — e o mesmo componente dá vida à entrada dos cards da Home, o que
/// mantém o vocabulário de movimento consistente.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppMotion.slow,
    this.offset = 16,
    this.curve = AppMotion.decelerate,
    this.enabled = true,
  });

  /// Constrói uma lista com atraso incremental entre os itens.
  static List<Widget> stagger(
    List<Widget> children, {
    Duration step = AppMotion.stagger,
    Duration initialDelay = Duration.zero,
    double offset = 16,
  }) {
    return List<Widget>.generate(children.length, (int i) {
      return Reveal(
        delay: initialDelay + step * i,
        offset: offset,
        child: children[i],
      );
    });
  }

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;
  final Curve curve;

  /// Quando `false`, o filho aparece imediatamente. Útil para respeitar a
  /// preferência de "reduzir movimento" do sistema.
  final bool enabled;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) {
      _controller.value = 1;
      return;
    }
    Future<void>.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Respeita a configuração de acessibilidade do sistema.
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion || !widget.enabled) return widget.child;

    final CurvedAnimation animation =
        CurvedAnimation(parent: _controller, curve: widget.curve);

    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        return Opacity(
          opacity: animation.value,
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - animation.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
