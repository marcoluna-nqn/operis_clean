// lib/services/atomic_json_store.dart
// Null-safety. Escritura ATÓMICA de JSON (+ flush + rename).
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AtomicJsonStore {
  AtomicJsonStore._();
  static Directory? _base;

  /// Directorio base: appDocuments/bitacorta_store
  static Future<Directory> _ensureBase() async {
    if (_base != null) return _base!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'bitacorta_store'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _base = dir;
    return dir;
  }

  static Future<File> _file(String name) async {
    final base = await _ensureBase();
    return File(p.join(base.path, '$name.json'));
  }

  /// Escribe JSON de forma atómica: tmp -> flush -> rename.
  static Future<void> writeAtomic(String name, Map<String, dynamic> json) async {
    final target = await _file(name);
    final tmp = File('${target.path}.tmp');
    final raf = await tmp.open(mode: FileMode.write);

    try {
      final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(json));
      await raf.writeFrom(bytes);
      await raf.flush();
      await raf.close();

      // rename es atómico dentro del mismo directorio en Android/Linux.
      if (await target.exists()) {
        // En algunos FS, rename no pisa; borramos primero para asegurar.
        await target.delete();
      }
      await tmp.rename(target.path);
    } finally {
      // Cierre defensivo (por si falló antes del close).
      try {
        await raf.close();
      } catch (_) {
        // Ignorado: ya estaba cerrado o no cerrable.
      }
      // Limpia el .tmp si quedó huérfano.
      try {
        if (await tmp.exists()) {
          await tmp.delete();
        }
      } catch (_) {
        // Ignorado.
      }
    }
  }

  /// Lee JSON. Si no existe o está corrupto, devuelve {}.
  static Future<Map<String, dynamic>> readOrEmpty(String name) async {
    final file = await _file(name);
    if (!await file.exists()) return <String, dynamic>{};
    try {
      final text = await file.readAsString();
      final data = jsonDecode(text);
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    } catch (_) {
      // Archivo corrupto: no propagamos. Devolvemos vacío.
      return <String, dynamic>{};
    }
  }
}
