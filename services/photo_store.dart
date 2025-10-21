// lib/services/photo_store.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../shared/sheet_limits.dart'; // kMaxPhotosTotal

/// Parámetros de compresión
const double kTargetMaxWH = 1024.0; // lado máximo
const int kJpegQuality = 80; // 1–100

class PhotoStoreResult {
  final File file;
  final int remainingInSheet;
  PhotoStoreResult(this.file, this.remainingInSheet);
}

class PhotoStore {
  PhotoStore._();

  // -------- helpers internos --------

  static String _sanitize(String raw) {
    final sb = StringBuffer();
    for (final r in raw.runes) {
      final c = String.fromCharCode(r);
      final code = c.codeUnitAt(0);
      final ok = (code >= 48 && code <= 57) || // 0-9
          (code >= 65 && code <= 90) || // A-Z
          (code >= 97 && code <= 122) || // a-z
          c == '-' ||
          c == '_';
      sb.write(ok ? c : '_');
    }
    final s = sb.toString();
    return s.isEmpty ? 'unknown' : s;
  }

  /// rowId estable. Solo String no vacío o numérico.
  static String _rowKey(Object rowId) {
    if (rowId is String) {
      final k = rowId.trim();
      if (k.isEmpty) {
        throw ArgumentError('rowId vacío. Usá una clave estable no vacía.');
      }
      return _sanitize(k);
    }
    if (rowId is num) {
      return _sanitize(rowId.toString());
    }
    throw ArgumentError(
      'rowId inválido (${rowId.runtimeType}). Debe ser String o num estable.',
    );
  }

  static Future<void> _cleanupStaleParts(Directory dir,
      {Duration maxAge = const Duration(hours: 24)}) async {
    if (!await dir.exists()) return;
    final now = DateTime.now();
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File && e.path.endsWith('.part')) {
          final st = await e.stat();
          if (now.difference(st.modified) > maxAge) {
            try {
              await e.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  /// Cola simple por clave para serializar operaciones de escritura/contador.
  static final Map<String, Future<void>> _tails = <String, Future<void>>{};
  static Future<T> _queue<T>(String key, Future<T> Function() task) {
    final prev = _tails[key] ?? Future<void>.value();
    final fut = prev.then((_) => task());
    _tails[key] = fut.then((_) {}).catchError((_) {});
    return fut;
  }

  // -------- estructura de carpetas --------

  /// Carpeta raíz para fotos de una planilla:
  /// AppDocs/sheets/<sheetId>/photos
  static Future<Directory> _sheetPhotosDir(String sheetId) async {
    final safe = _sanitize(sheetId);
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'sheets', safe, 'photos'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Carpeta por fila:
  /// AppDocs/sheets/<sheetId>/photos/<rowKey>/
  static Future<Directory> _rowDir(String sheetId, Object rowId) async {
    final root = await _sheetPhotosDir(sheetId);
    final dir = Directory(p.join(root.path, _rowKey(rowId)));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Renombra la clave de una fila y mueve sus fotos.
  static Future<void> renameRowKey({
    required String sheetId,
    required Object fromRowId,
    required Object toRowId,
  }) async {
    final root = await _sheetPhotosDir(sheetId);
    final from = Directory(p.join(root.path, _rowKey(fromRowId)));
    final to = Directory(p.join(root.path, _rowKey(toRowId)));
    if (!await from.exists()) return;
    if (await to.exists()) {
      await for (final e in from.list()) {
        if (e is File) {
          final dest = File(p.join(to.path, p.basename(e.path)));
          await e.copy(dest.path);
          try { await e.delete(); } catch (_) {}
        }
      }
      try { await from.delete(recursive: true); } catch (_) {}
    } else {
      await from.rename(to.path);
    }
  }

  // -------- consultas --------

  /// Cuenta fotos totales de una planilla (recursivo).
  static Future<int> countSheetPhotos(String sheetId) async {
    final root = await _sheetPhotosDir(sheetId);
    if (!await root.exists()) return 0;
    int count = 0;
    await for (final ent in root.list(recursive: true, followLinks: false)) {
      if (ent is File && _isImagePath(ent.path)) count++;
    }
    return count;
  }

  /// Lista fotos de una fila.
  static Future<List<File>> listRowPhotos(String sheetId, Object rowId) async {
    final dir = await _rowDir(sheetId, rowId);
    if (!await dir.exists()) return [];
    final all = await dir.list().toList();
    return all.whereType<File>().where((f) => _isImagePath(f.path)).toList();
  }

  /// Elimina una foto por ruta.
  static Future<void> deletePhoto(String path) async {
    final f = File(path);
    if (await f.exists()) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  static bool _isImagePath(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.jpg' || ext == '.jpeg' || ext == '.png' || ext == '.webp';
  }

  // -------- escritura --------

  /// Guarda y comprime XFile de la cámara usando isolate (compute).
  /// Respeta límite total por planilla. Escritura atómica .part -> rename().
  static Future<PhotoStoreResult> saveCameraXFile({
    required XFile xfile,
    required String sheetId,
    required Object rowId, // String o num ESTABLE
  }) {
    final key = 'ps:${_sanitize(sheetId)}';
    return _queue<PhotoStoreResult>(key, () async {
      // valida temprano
      final _ = _rowKey(rowId);

      final current = await countSheetPhotos(sheetId);
      if (current >= kMaxPhotosTotal) {
        throw StateError('Límite alcanzado ($kMaxPhotosTotal) para la planilla $sheetId.');
      }

      final dir = await _rowDir(sheetId, rowId);
      await _cleanupStaleParts(dir);

      final ts = DateTime.now().microsecondsSinceEpoch;
      final rnd = (math.Random().nextInt(0xFFFF)).toRadixString(16).padLeft(4, '0');
      final baseName = 'IMG_${ts}_$rnd.jpg';
      final finalPath = p.join(dir.path, baseName);
      final tmpPath = '$finalPath.part';

      // Leer bytes y comprimir en otro isolate.
      final srcBytes = await xfile.readAsBytes();
      Uint8List jpgBytes;
      try {
        jpgBytes = await compute(_compressJpegIsolate, <String, Object>{
          'bytes': srcBytes,
          'maxWH': kTargetMaxWH,
          'quality': kJpegQuality,
        });
      } catch (_) {
        jpgBytes = srcBytes;
      }

      // Escritura atómica con fsync.
      final tmpFile = File(tmpPath);
      final raf = await tmpFile.open(mode: FileMode.write);
      try {
        await raf.writeFrom(jpgBytes);
        await raf.flush();
      } finally {
        await raf.close();
      }

      // Si quedó vacío, fallback a bytes originales.
      if ((await tmpFile.length()) == 0) {
        final raf2 = await tmpFile.open(mode: FileMode.write);
        try {
          await raf2.writeFrom(srcBytes);
          await raf2.flush();
        } finally {
          await raf2.close();
        }
      }

      // rename en el mismo directorio es atómico. Copiar si falla.
      try {
        await tmpFile.rename(finalPath);
      } on FileSystemException {
        await File(finalPath).writeAsBytes(await tmpFile.readAsBytes(), flush: true);
        try { await tmpFile.delete(); } catch (_) {}
      }

      final out = File(finalPath);
      if (!await out.exists() || (await out.length()) == 0) {
        throw FileSystemException('Archivo no quedó grabado', finalPath);
      }

      final remaining = math.max(0, kMaxPhotosTotal - (current + 1));
      return PhotoStoreResult(out, remaining);
    });
  }
}

/// Función top-level para compute. No captura estado.
/// Recibe: {'bytes': Uint8List, 'maxWH': double, 'quality': int}
Future<Uint8List> _compressJpegIsolate(Map<String, Object> args) async {
  final bytes = args['bytes'] as Uint8List;
  final maxWH = args['maxWH'] as double;
  final quality = args['quality'] as int;

  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  // Corregir orientación EXIF.
  img.Image oriented = img.bakeOrientation(decoded);

  // Redimensionar manteniendo aspecto.
  final w = oriented.width.toDouble();
  final h = oriented.height.toDouble();
  final maxSide = math.max(w, h);
  if (maxSide > maxWH) {
    final scale = maxWH / maxSide;
    oriented = img.copyResize(
      oriented,
      width: (w * scale).round(),
      height: (h * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }

  final out = img.encodeJpg(oriented, quality: quality);
  return Uint8List.fromList(out);
}
