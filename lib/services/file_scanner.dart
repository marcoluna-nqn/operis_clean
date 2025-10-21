// lib/services/file_scanner.dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Info del archivo exportado que la UI espera.
class FileInfo {
  final File file;
  final String origin; // p.ej. "Documentos" / "Temp"
  final int sizeBytes;
  final DateTime modified;

  FileInfo({
    required this.file,
    required this.origin,
    required this.sizeBytes,
    required this.modified,
  });

  String get name => p.basename(file.path);
  String get ext => p.extension(file.path).toLowerCase();
}

/// Escanea directorios típicos de la app por reportes/exportaciones.
Future<List<FileInfo>> scanReports() async {
  final docsDir = await getApplicationDocumentsDirectory();
  final tmpDir = await getTemporaryDirectory();

  final exts = <String>{'.xlsx', '.xls', '.csv', '.pdf'};
  final out = <FileInfo>[];

  Future<void> scanDir(Directory dir, String origin) async {
    if (!await dir.exists()) return;
    await for (final ent in dir.list(recursive: true, followLinks: false)) {
      if (ent is! File) continue;
      final ext = p.extension(ent.path).toLowerCase();
      if (!exts.contains(ext)) continue;
      try {
        final stat = await ent.stat();
        out.add(FileInfo(
          file: ent,
          origin: origin,
          sizeBytes: stat.size,
          modified: stat.modified,
        ));
      } catch (_) {
        // ignorar archivos inaccesibles
      }
    }
  }

  await scanDir(docsDir, 'Documentos');
  await scanDir(tmpDir, 'Temp');

  out.sort((a, b) => b.modified.compareTo(a.modified));
  return out;
}

/// Formatea tamaños (ej: 1.2 MB)
String formatSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  double size = bytes.toDouble();
  int unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return unit == 0
      ? '$bytes ${units[unit]}'
      : '${size.toStringAsFixed(1)} ${units[unit]}';
}
