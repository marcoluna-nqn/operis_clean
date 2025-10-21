// lib/services/sheet_registry.dart
import '../models/sheet.dart';
import 'sheets_repository.dart';

/// Registro simple para planillas, con repo inyectado.
class SheetRegistry {
  SheetRegistry._(this._repo);
  static SheetRegistry? _instance;
  static bool _inited = false;

  final SheetsRepository _repo;

  /// Inicializa una sola vez.
  static void init(SheetsRepository repo) {
    if (_inited && _instance != null) return;
    _instance = SheetRegistry._(repo);
    _inited = true;
  }

  /// Acceso seguro.
  static SheetRegistry get instance {
    if (_instance == null) {
      throw StateError(
          'SheetRegistry no inicializado. LlamÃƒÆ’Ã‚Â¡ SheetRegistry.init(repo).');
    }
    return _instance!;
  }

  Future<List<Sheet>> getAllSorted() => _repo.listSheets();
  Future<Sheet> create({required String name}) => _repo.createSheet(name: name);
  Future<void> remove(int id) => _repo.deleteSheet(id);

  /// Compatibilidad con llamadas existentes.
  Future<void> touch(Object _) async {}
}
