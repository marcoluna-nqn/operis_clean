class Sheet {
  final int id;
  String name;
  final int createdAt; // epoch ms

  Sheet({required this.id, required this.name, required this.createdAt});

  Sheet copyWith({String? name}) =>
      Sheet(id: id, name: name ?? this.name, createdAt: createdAt);
}

/// DB en memoria (placeholder).
class LocalDb {
  LocalDb._();
  static final LocalDb I = LocalDb._();

  final List<Sheet> _sheets = [];
  int _nextId = 1;

  Future<List<Sheet>> listSheets() async => List<Sheet>.unmodifiable(_sheets);

  Future<int> insertSheet(String name) async {
    final s = Sheet(
      id: _nextId++,
      name: name,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _sheets.add(s);
    return s.id;
  }

  Future<void> deleteSheet(int id) async {
    _sheets.removeWhere((e) => e.id == id);
  }

  Future<Sheet?> getSheet(int id) async =>
      _sheets.where((e) => e.id == id).cast<Sheet?>().firstOrNull;

  Future<void> updateSheetName(int id, String name) async {
    final idx = _sheets.indexWhere((e) => e.id == id);
    if (idx >= 0) _sheets[idx] = _sheets[idx].copyWith(name: name);
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
