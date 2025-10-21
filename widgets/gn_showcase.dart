import 'package:flutter/widgets.dart';

/// Stub minimal de "showcase" para compilar sin el paquete externo.
/// Evita conflictos con otras clases llamadas Showcase/ShowCaseWidget.
class _GnShowcaseController {
  void startShowCase(List<GlobalKey> _) {}
}

class GnShowCaseWidget extends StatelessWidget {
  const GnShowCaseWidget({super.key, required this.builder});
  final WidgetBuilder builder;

  static _GnShowcaseController of(BuildContext _) => _GnShowcaseController();

  @override
  Widget build(BuildContext context) => builder(context);
}

class GnShowcase extends StatelessWidget {
  const GnShowcase({
    super.key,
    required this.child,
    this.title,
    this.description,
  });

  final Widget child;
  final String? title;
  final String? description;

  @override
  Widget build(BuildContext context) => child;
}
