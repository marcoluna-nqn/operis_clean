// lib/core/gn_scroll_behavior.dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// ScrollBehavior con:
/// - Rebote estilo iOS/macOS (opcional en todas las plataformas).
/// - Sin "glow" azul en Android.
/// - Scrollbar sólo en desktop para mejor usabilidad con mouse/trackpad.
class GNScrollBehavior extends ScrollBehavior {
  const GNScrollBehavior({
    this.alwaysBounce = false,
    this.desktopScrollbar = true,
  });

  /// Si true, fuerza BouncingScrollPhysics en todas las plataformas.
  final bool alwaysBounce;

  /// Muestra Scrollbar en Windows/Linux/macOS.
  final bool desktopScrollbar;

  @override
  Widget buildOverscrollIndicator(
      BuildContext context,
      Widget child,
      ScrollableDetails details,
      ) {
    // Suprime el glow en todas las plataformas (iOS ya no lo usa).
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final platform = Theme.of(context).platform;
    final wantsBounce = alwaysBounce ||
        platform == TargetPlatform.iOS ||
        platform == TargetPlatform.macOS;

    return wantsBounce
        ? const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())
        : const ClampingScrollPhysics();
  }

  @override
  Widget buildScrollbar(
      BuildContext context,
      Widget child,
      ScrollableDetails details,
      ) {
    if (!desktopScrollbar) return child;

    final platform = Theme.of(context).platform;
    final isDesktop = platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS;

    if (!isDesktop) return child;

    return Scrollbar(
      controller: details.controller,
      interactive: true,
      thumbVisibility: true,
      radius: const Radius.circular(8),
      child: child,
    );
  }

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };
}

/// Helper para aplicar el comportamiento fácilmente en cualquier subtree.
class GNScrollConfig extends StatelessWidget {
  const GNScrollConfig({
    super.key,
    this.behavior = const GNScrollBehavior(),
    required this.child,
  });

  final ScrollBehavior behavior;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(behavior: behavior, child: child);
  }
}
