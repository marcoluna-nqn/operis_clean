// lib/models/sheet.dart
class Sheet {
  final int id;
  final String name;

  /// Epoch (ms)
  final int createdAt;

  const Sheet({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  Sheet copyWith({
    int? id,
    String? name,
    int? createdAt,
  }) {
    return Sheet(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
