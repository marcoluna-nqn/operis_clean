import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FileDraftStore {
  Future<File> _fileFor(String id) async {
    final dir = await getApplicationSupportDirectory(); // sandbox privado
    final draftsDir = Directory(p.join(dir.path, 'drafts'));
    if (!await draftsDir.exists()) {
      await draftsDir.create(recursive: true);
    }
    return File(p.join(draftsDir.path, '$id.json'));
  }

  /// Carga el draft (o null si no existe / está corrupto).
  Future<Map<String, dynamic>?> load(String id) async {
    try {
      final f = await _fileFor(id);
      if (!await f.exists()) return null;
      final raw = await f.readAsString();
      if (raw.isEmpty) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Guarda con escritura atómica (tmp -> rename) para evitar archivos truncados.
  Future<void> save(String id, Map<String, dynamic> data) async {
    final f = await _fileFor(id);
    final tmp = File('${f.path}.tmp');
    final json = const JsonEncoder.withIndent('  ').convert(data);

    // escribe a tmp y fuerza a disco
    final raf = await tmp.open(mode: FileMode.write);
    await raf.writeString(json);
    await raf.flush();
    await raf.close();

    // reemplazo atómico
    if (await f.exists()) {
      await f.delete(); // en Android/Linux, rename sobre existente puede fallar
    }
    await tmp.rename(f.path);
  }

  Future<void> delete(String id) async {
    final f = await _fileFor(id);
    if (await f.exists()) await f.delete();
  }

  /// Limpia todo (opcional).
  Future<void> deleteAll() async {
    final dir = await getApplicationSupportDirectory();
    final draftsDir = Directory(p.join(dir.path, 'drafts'));
    if (await draftsDir.exists()) {
      await draftsDir.delete(recursive: true);
    }
  }
}
