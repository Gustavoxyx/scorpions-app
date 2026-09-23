import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_motion.dart';

/// Transições de página do produto.
///
/// Três gestos apenas — e cada um significa uma coisa. Isso é o que faz a
/// navegação "parecer o mesmo aplicativo" em todas as telas.
abstract final class AppTransitions {
  /// Avanço dentro de um fluxo: desliza da direita com desvanecimento.
  static CustomTransitionPage<T> forward<T>({
    required LocalKey key,
    required Widget child,
  }) {
    return CustomTransitionPage<T>(
      key: key,
      transitionDuration: AppMotion.page,
      reverseTransitionDuration: AppMotion.base,
      child: child,
      transitionsBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondary,
        Widget child,
      ) {
        final Animation<double> curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.emphasized,
          reverseCurve: AppMotion.standard,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.06, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  /// Troca de contexto (splash, onboarding, autenticação): apenas fade.
  static CustomTransitionPage<T> fade<T>({
    required LocalKey key,
    required Widget child,
  }) {
    return CustomTransitionPage<T>(
      key: key,
      transitionDuration: AppMotion.base,
      reverseTransitionDuration: AppMotion.base,
      child: child,
      transitionsBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondary,
        Widget child,
      ) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  /// Entrada de tela em tela cheia (câmera, análise): sobe de baixo.
  ///
  /// A câmera "abre" — não "desliza ao lado" — porque é uma mudança de modo,
  /// não uma continuação da mesma lista.
  static CustomTransitionPage<T> modal<T>({
    required LocalKey key,
    required Widget child,
  }) {
    return CustomTransitionPage<T>(
      key: key,
      transitionDuration: AppMotion.page,
      reverseTransitionDuration: AppMotion.base,
      child: child,
      transitionsBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondary,
        Widget child,
      ) {
        final Animation<double> curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.emphasized,
          reverseCurve: AppMotion.standard,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
              child: child,
            ),
          ),
        );
      },
    );
  }

  /// Troca entre abas: sem deslocamento, só desvanecimento cruzado.
  static CustomTransitionPage<T> tab<T>({
    required LocalKey key,
    required Widget child,
  }) =>
      fade<T>(key: key, child: child);
}
