// lib/services/backup_service.dart
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/app_db.dart';

class BackupService {
  BackupService._();
  static final BackupService I = BackupService._();

  Directory? _backupDir;
  bool _busy = false;

  Future<void> init() async {
    final app = await getApplicationSupportDirectory();
    _backupDir = Directory(p.join(app.path, 'backups'));
    _backupDir!.createSync(recursive: true);
  }

  Future<File> makeBackup({int keepLast = 10}) async {
    if (_backupDir == null) await init();
    if (_busy) throw StateError('Backup en progreso');
    _busy = true;
    try {
      final dbFile = await AppDb.dbFile();
      final media = await AppDb.mediaDir();

      final ts = DateFormat("yyyyMMdd_HHmmss").format(DateTime.now());
      final out = File(p.join(_backupDir!.path, 'bitacora_backup_$ts.zip'));

      final encoder = ZipFileEncoder();
      encoder.create(out.path);
      if (dbFile.existsSync()) encoder.addFile(dbFile);
      if (media.existsSync()) encoder.addDirectory(media, includeDirName: true);
      encoder.close();

      await _trimOldBackups(keepLast: keepLast);
      return out;
    } finally {
      _busy = false;
    }
  }

  Future<void> _trimOldBackups({required int keepLast}) async {
    final files = _backupDir!
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.zip'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    for (var i = keepLast; i < files.length; i++) {
      try { files[i].deleteSync(); } catch (_) {}
    }
  }

  /// (Opcional) Restaurar DB y media desde un .zip
  Future<void> restoreFromZip(File zipFile) async {
    final app = await getApplicationSupportDirectory();
    final dbFile = await AppDb.dbFile();
    final media = await AppDb.mediaDir();

    // Cerrar DB si fuera necesario (en este diseño se vuelve a abrir solo).
    // Borramos actuales:
    if (dbFile.existsSync()) dbFile.deleteSync();
    if (media.existsSync()) media.deleteSync(recursive: true);

    final bytes = zipFile.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final f in archive) {
      final outPath = p.join(app.path, f.name);
      if (f.isFile) {
        final outFile = File(outPath)..createSync(recursive: true);
        outFile.writeAsBytesSync(f.content as List<int>);
      } else {
        Directory(outPath).createSync(recursive: true);
      }
    }
  }

  Future<Directory> backupsFolder() async {
    if (_backupDir == null) await init();
    return _backupDir!;
  }
}
