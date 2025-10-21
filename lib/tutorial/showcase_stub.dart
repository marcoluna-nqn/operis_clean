import 'package:flutter/widgets.dart';

class ShowCaseWidget extends StatelessWidget {
  final WidgetBuilder builder;
  final double? blurValue;
  final bool? autoPlay;
  const ShowCaseWidget({super.key, required this.builder, this.blurValue, this.autoPlay});
  @override
  Widget build(BuildContext context) => builder(context);

  static _ShowcaseController of(BuildContext context) => _ShowcaseController();
}

class _ShowcaseController { void startShowCase(List<GlobalKey> _) {} }

class Showcase extends StatelessWidget {
  final Widget child;
  final String? description;
  const Showcase({super.key, required this.child, this.description});
  @override
  Widget build(BuildContext context) => child;
}
