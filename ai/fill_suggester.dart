// lib/services/fill_suggester.dart
import 'package:flutter/foundation.dart';

@immutable
class FillSuggestion with DiagnosticableTreeMixin {
  // No const en el ctor para permitir valores no-const sin errores.
  FillSuggestion({
    this.field = '',
    this.value,
    this.confidence = 1.0,
    this.source,
  });

  final String field;
  final Object? value;
  final double confidence; // 0..1
  final String? source;    // p. ej. "gps", "vision", "stt"

  FillSuggestion copyWith({
    String? field,
    Object? value,
    double? confidence,
    String? source,
  }) {
    return FillSuggestion(
      field: field ?? this.field,
      value: value ?? this.value,
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('field', field))
      ..add(DiagnosticsProperty<Object?>('value', value))
      ..add(DoubleProperty('confidence', confidence))
      ..add(StringProperty('source', source));
  }

  @override
  bool operator ==(Object other) {
    return other is FillSuggestion &&
        other.field == field &&
        other.value == value &&
        other.confidence == confidence &&
        other.source == source;
  }

  @override
  int get hashCode => Object.hash(field, value, confidence, source);
}

class FillSuggester {
  const FillSuggester();

  /// Devuelve sugerencias calculadas. Por defecto, ninguna.
  List<FillSuggestion> suggest([dynamic a, dynamic b]) => const <FillSuggestion>[];
}
