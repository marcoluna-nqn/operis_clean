// lib/services/ai/schemas.dart
class RowDraft {
  final String descripcion;
  final double? lat, lng, accuracyM;
  final List<String> tags;
  RowDraft({
    required this.descripcion,
    this.lat,
    this.lng,
    this.accuracyM,
    this.tags = const [],
  });

  RowDraft validate() {
    final d = descripcion.trim();
    final okGeo = lat != null &&
        lng != null &&
        lat!.isFinite &&
        lng!.isFinite &&
        lat != 0 &&
        lng != 0;
    return RowDraft(
      descripcion: d.isEmpty ? 'Incidencia' : d,
      lat: okGeo ? lat : null,
      lng: okGeo ? lng : null,
      accuracyM: accuracyM,
      tags: tags.where((e) => e.trim().isNotEmpty).toSet().take(8).toList(),
    );
  }

  Map<String, dynamic> toRowValues() => {
        'descripcion': descripcion,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (accuracyM != null) 'accuracy_m': accuracyM,
        if (tags.isNotEmpty) 'tags': tags,
        'ts': DateTime.now().toIso8601String(),
      };
}
