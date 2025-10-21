// lib/widgets/showcase_stub.dart
// Stub sin dependencias. No ejecuta tutoriales.

import 'package:flutter/material.dart';

class GNShowCaseWidget extends StatelessWidget {
  final WidgetBuilder builder;
  final double? blurValue;
  const GNShowCaseWidget({
    super.key,
    required this.builder,
    this.blurValue,
  });

  static _GNShowcaseController of(BuildContext context) =>
      const _GNShowcaseController();

  @override
  Widget build(BuildContext context) => builder(context);
}

class _GNShowcaseController {
  const _GNShowcaseController();
  void startShowCase(List<GlobalKey> keys) {
    // no-op
  }
}

class GNShowcase extends StatelessWidget {
  final Widget child;
  final String? title;
  final String? description;

  const GNShowcase({
    super.key,
    required this.child,
    this.title,
    this.description,
  });

  @override
  Widget build(BuildContext context) => child;
}
