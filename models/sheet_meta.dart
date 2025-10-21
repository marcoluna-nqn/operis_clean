// lib/models/sheet_meta.dart

/// Metadatos simples de una planilla.
class SheetMeta {
  final int id; // identificador de la planilla
  final String name; // nombre visible
  final int createdAt; // epoch-ms (consistente con tus pantallas)
  final String? description; // opcional

  const SheetMeta({
    required this.id,
    required this.name,
    required this.createdAt,
    this.description,
  });

  SheetMeta copyWith({
    int? id,
    String? name,
    int? createdAt,
    String? description,
  }) {
    return SheetMeta(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      description: description ?? this.description,
    );
  }

  // ---- (De)serialización ----
  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'createdAt': createdAt,
        'description': description,
      };

  factory SheetMeta.fromMap(Map<String, Object?> map) => SheetMeta(
        id: (map['id'] as num).toInt(),
        name: (map['name'] ?? '') as String,
        createdAt: (map['createdAt'] as num).toInt(),
        description: map['description'] as String?,
      );

  Map<String, Object?> toJson() => toMap();
  factory SheetMeta.fromJson(Map<String, Object?> json) =>
      SheetMeta.fromMap(json);

  @override
  String toString() => 'SheetMeta(id: $id, name: $name, createdAt: $createdAt)';
}
