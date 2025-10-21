// lib/services/ai/schemas.dart
class RowDraft {
  final String descripcion;
  final double? lat;
  final double? lng;
  final double accuracyM;
  final List<String> tags;

  RowDraft({
    required this.descripcion,
    this.lat,
    this.lng,
    this.accuracyM = 30.0,
    List<String>? tags,
  }) : tags = (tags ?? const <String>[]).map((e) => e.toString()).toSet().toList();

  /// En tu caso no hay validaciones complejas: devolvemos una copia “normalizada”.
  RowDraft validate() => RowDraft(
    descripcion: descripcion.trim(),
    lat: lat,
    lng: lng,
    accuracyM: accuracyM,
    tags: tags.toSet().toList(),
  );

  /// Lo que consume `Copilot._toMeasurement(...)`
  Map<String, dynamic> toRowValues() => <String, dynamic>{
    'observations': descripcion,
    'lat': lat,
    'lng': lng,
    'accuracyM': accuracyM,
    'tags': tags,
  };
}
