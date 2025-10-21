import '../data/app_db.dart';

class SheetsRepo {
  SheetsRepo(this.db);
  final AppDb db;

  static const String defaultId = 'default';

  SheetData? _cache;

  /// Crea la hoja default si no existe y precrea [initialRows] filas vacías.
  Future<SheetData> initIfNeeded({int columns = 5, int initialRows = 60}) async {
    final existing = await db.fetchSheet(defaultId);
    if (existing != null) {
      _cache = existing;
      return existing;
    }

    await db.upsertSheet(
      id: defaultId,
      columns: columns,
      headers: List.filled(columns, ''),
    );

    // Precrear filas vacías (mantiene el scroll fluido)
    for (var i = 0; i < initialRows; i++) {
      await db.addRow(defaultId, i, List.filled(columns, ''));
    }

    final created = await db.fetchSheet(defaultId);
    _cache = created;
    return created!;
  }

  Future<SheetData?> get({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null) return _cache;
    _cache = await db.fetchSheet(defaultId);
    return _cache;
  }

  Future<void> setHeaders(List<String> headers) async {
    await db.upsertSheet(
      id: defaultId,
      headers: headers,
      columns: headers.length,
    );
    _cache = await db.fetchSheet(defaultId);
  }

  Future<RowData> addRow(List<String> cells, int index) async {
    final id = await db.addRow(defaultId, index, cells);
    // Traemos la hoja para devolver el RowData real de DB (evita desincronización)
    final s = await db.fetchSheet(defaultId);
    _cache = s;
    return s!.rows.firstWhere((r) => r.id == id);
  }

  Future<void> saveRow(RowData r) async {
    await db.updateRow(r);
    _cache = await db.fetchSheet(defaultId);
  }

  Future<void> removeRow(RowData r) async {
    await db.deleteRow(r.id);
    _cache = await db.fetchSheet(defaultId);
  }

  /// Helper: agrega [count] filas vacías al final.
  Future<void> addEmptyRows(int count) async {
    final s = await get(forceRefresh: true);
    final cols = s?.columns ?? 5;
    final start = s?.rows.length ?? 0;
    for (var i = 0; i < count; i++) {
      await db.addRow(defaultId, start + i, List.filled(cols, ''));
    }
    _cache = await db.fetchSheet(defaultId);
  }
}
