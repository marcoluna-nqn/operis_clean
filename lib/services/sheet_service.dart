import 'dart:convert';

class SheetMeta {
  final String id;
  String name;
  DateTime createdAt;
  double? latitude;
  double? longitude;

  SheetMeta({
    required this.id,
    required this.name,
    DateTime? createdAt,
    this.latitude,
    this.longitude,
  }) : createdAt = createdAt ?? DateTime.now();

  SheetMeta copyWith({
    String? name,
    DateTime? createdAt,
    double? latitude,
    double? longitude,
  }) {
    return SheetMeta(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
  };

  static SheetMeta fromJson(Map<String, dynamic> j) => SheetMeta(
    id: (j['id'] ?? '') as String,
    name: (j['name'] ?? 'Planilla') as String,
    createdAt:
    DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    latitude: (j['latitude'] as num?)?.toDouble(),
    longitude: (j['longitude'] as num?)?.toDouble(),
  );

  static String encodeList(List<SheetMeta> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<SheetMeta> decodeList(String s) {
    final raw = (jsonDecode(s) as List).cast<Map<String, dynamic>>();
    return raw.map(SheetMeta.fromJson).toList();
  }
}
