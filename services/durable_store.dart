import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Cola simple de I/O por clave para serializar operaciones (evita carreras).
class _IoQueue {
  static final Map<String, Future<void>> _tails = <String, Future<void>>{};

  static Future<T> run<T>(String key, Future<T> Function() task) {
    final prev = _tails[key] ?? Future<void>.value();
    final future = prev.then((_) => task());
    // Mantener la cola: tail "void" que no propaga errores
    _tails[key] = future.then((_) {}).catchError((_) {});
    return future;
  }
}

/// Adler-32: checksum rápido sin dependencias.
int _adler32(Uint8List data) {
  const int mod = 65521;
  int a = 1, b = 0;
  for (final v in data) {
    a += v;
    if (a >= mod) a -= mod;
    b += a;
    if (b >= mod) b %= mod;
  }
  return (b << 16) | a;
}

String _hex32(int x) => x.toRadixString(16).padLeft(8, '0');

class AtomicJsonStore {
  // Alineado con CrashGuard: <AppSupport>/bitacora
  static Future<Directory> _baseDir() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory(p.join(root.path, 'bitacora'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _safeName(String name) {
    final s = name.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return s.isEmpty ? 'store' : s;
  }

  static Future<File> _mainFile(String name) async {
    final dir = await _baseDir();
    return File(p.join(dir.path, '${_safeName(name)}.json'));
  }

  static Future<File> _sumFileFor(File f) async => File('${f.path}.sum');

  static Future<Directory> _snapDir(String name) async {
    final dir = await _baseDir();
    final d = Directory(p.join(dir.path, '_snapshots', _safeName(name)));
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return d;
  }

  /// Escritura atómica + snapshotting + checksum (Adler-32).
  ///
  /// [keep]: cantidad de snapshots a conservar por recencia.
  /// [keepBytes]: poda extra por tamaño total aproximado (borra los más viejos).
  /// [maxAge]: borra snapshots más viejos que esa antigüedad.
  static Future<void> writeAtomicWithSnapshots(
      String name,
      Map<String, dynamic> json, {
        int keep = 5,
        int? keepBytes,
        Duration? maxAge,
      }) {
    return _IoQueue.run('store:$name', () async {
      final file = await _mainFile(name);
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final bytes = Uint8List.fromList(const Utf8Encoder().convert(jsonEncode(json)));
      final tmp = File('${file.path}.part');

      // Escribir a .part con fsync
      final raf = await tmp.open(mode: FileMode.write);
      try {
        await raf.writeFrom(bytes);
        await raf.flush();
      } finally {
        await raf.close();
      }

      // Renombrado atómico con fallback a .bak
      Future<void> replaceWithTmp() async {
        try {
          await tmp.rename(file.path);
        } on FileSystemException {
          final bak = File('${file.path}.bak');
          if (await bak.exists()) {
            try {
              await bak.delete();
            } catch (_) {}
          }
          if (await file.exists()) {
            try {
              await file.rename(bak.path);
            } catch (_) {}
          }
          try {
            await tmp.rename(file.path);
            if (await bak.exists()) {
              unawaited(bak.delete());
            }
          } catch (_) {
            if (await bak.exists()) {
              try {
                if (await file.exists()) {
                  await file.delete();
                }
                await bak.rename(file.path);
              } catch (_) {}
            }
            rethrow;
          }
        }
      }

      await replaceWithTmp();

      // Escribir checksum sidecar del archivo principal
      final sumMain = await _sumFileFor(file);
      final adler = _adler32(bytes);
      await sumMain.writeAsString('${bytes.length}:${_hex32(adler)}', flush: true);

      // Snapshot
      final snapDir = await _snapDir(name);
      final ts = DateTime.now().toIso8601String().replaceAll(':', '').replaceAll('.', '');
      final snap = File(p.join(snapDir.path, '${_safeName(name)}-$ts.json'));
      await snap.writeAsBytes(bytes, flush: true);
      // Checksum del snapshot
      final sumSnap = await _sumFileFor(snap);
      await sumSnap.writeAsString('${bytes.length}:${_hex32(adler)}', flush: true);

      // Poda de snapshots
      try {
        final allEntities = await snapDir.list().toList();
        final files =
        allEntities.whereType<File>().where((f) => f.path.endsWith('.json')).toList();

        final withTimes = <_FStat>[];
        for (final f in files) {
          try {
            final m = await f.lastModified();
            final s = await f.length();
            withTimes.add(_FStat(file: f, mtime: m, size: s));
          } catch (_) {}
        }

        // Ordenar por recencia (desc)
        withTimes.sort((a, b) => b.mtime.compareTo(a.mtime));

        final toDelete = <_FStat>[];

        // 1) Mantener los más recientes según 'keep' (mínimo 1)
        final keepClamped = keep < 1 ? 1 : keep;
        if (withTimes.length > keepClamped) {
          toDelete.addAll(withTimes.sublist(keepClamped));
        }

        // 2) Poda por antigüedad
        if (maxAge != null) {
          final cutoff = DateTime.now().subtract(maxAge);
          for (final st in withTimes) {
            if (st.mtime.isBefore(cutoff) && !toDelete.contains(st)) {
              toDelete.add(st);
            }
          }
        }

        // 3) Poda por tamaño total
        if (keepBytes != null && keepBytes > 0) {
          final survivors = withTimes.where((s) => !toDelete.contains(s)).toList();
          var total = survivors.fold<int>(0, (acc, s) => acc + s.size);
          if (total > keepBytes) {
            for (var i = survivors.length - 1; i >= 0 && total > keepBytes; i--) {
              final st = survivors[i];
              if (!toDelete.contains(st)) {
                toDelete.add(st);
                total -= st.size;
              }
            }
          }
        }

        // Ejecutar borrados (+ sus .sum)
        for (final st in toDelete) {
          try {
            await st.file.delete();
          } catch (_) {}
          try {
            final sum = await _sumFileFor(st.file);
            if (await sum.exists()) {
              await sum.delete();
            }
          } catch (_) {}
        }
      } catch (_) {}
    });
  }

  /// Lectura resiliente: intenta principal, .part, .bak y snapshots; valida checksum si existe.
  static Future<Map<String, dynamic>> readResilient(String name) async {
    return _IoQueue.run('store:$name', () async {
      final main = await _mainFile(name);

      // Recuperación básica: promover .part si falta el main; restaurar .bak si aplica.
      await _recoverIfNeeded(main);

      final cand = <File>[
        main,
        File('${main.path}.part'), // por si quedó pendiente entre flush y rename
        File('${main.path}.bak'),
      ];

      Future<Map<String, dynamic>?> tryRead(File f) async {
        if (!await f.exists()) return null;
        try {
          final txt = await f.readAsString();
          final obj = jsonDecode(txt);
          if (obj is Map) {
            // Validar checksum si existe sidecar (no habrá .sum para .part normalmente)
            final sumFile = await _sumFileFor(f);
            if (await sumFile.exists()) {
              try {
                final meta = (await sumFile.readAsString()).trim();
                final parts = meta.split(':');
                if (parts.length == 2) {
                  final expectedLen = int.tryParse(parts[0]);
                  final expectedHex = parts[1];
                  final raw = Uint8List.fromList(const Utf8Encoder().convert(txt));
                  if (expectedLen == raw.length &&
                      _hex32(_adler32(raw)) == expectedHex) {
                    return Map<String, dynamic>.from(obj);
                  } else {
                    // checksum falló → considerar corrupto
                    return null;
                  }
                }
              } catch (_) {
                // si el .sum está corrupto, intentar de todos modos (fallback suave)
                return Map<String, dynamic>.from(obj);
              }
            } else {
              // sin sum: aceptar
              return Map<String, dynamic>.from(obj);
            }
          }
        } catch (_) {}
        return null;
      }

      for (final f in cand) {
        final j = await tryRead(f);
        if (j != null) return j;
      }

      // Snapshots por recencia
      final snapDir = await _snapDir(name);
      try {
        final entities = await snapDir.list().toList();
        final files =
        entities.whereType<File>().where((f) => f.path.endsWith('.json')).toList();

        final withTimes = <_FStat>[];
        for (final f in files) {
          try {
            final m = await f.lastModified();
            withTimes.add(_FStat(file: f, mtime: m, size: await f.length()));
          } catch (_) {}
        }
        withTimes.sort((a, b) => b.mtime.compareTo(a.mtime));

        for (final st in withTimes) {
          final j = await tryRead(st.file);
          if (j != null) return j;
        }
      } catch (_) {}

      return <String, dynamic>{};
    });
  }

  /// Borra todos los snapshots del store (mantenimiento manual).
  static Future<void> deleteAllSnapshots(String name) async {
    final dir = await _snapDir(name);
    try {
      final entries = await dir.list().toList();
      for (final e in entries) {
        if (e is File &&
            (e.path.endsWith('.json') || e.path.endsWith('.json.sum'))) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  static Future<void> _recoverIfNeeded(File mainFile) async {
    final part = File('${mainFile.path}.part');
    final bak = File('${mainFile.path}.bak');

    // Si no hay main pero hay .part -> promover
    if (!await mainFile.exists() && await part.exists()) {
      try {
        await part.rename(mainFile.path);
      } catch (_) {}
    }

    // Si sigue sin main y hay .bak -> restaurar
    if (!await mainFile.exists() && await bak.exists()) {
      try {
        await bak.rename(mainFile.path);
      } catch (_) {}
    }

    // Limpieza: si ya hay main, eliminar restos obvios
    if (await mainFile.exists()) {
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
    }
  }
}

class JsonOpLog {
  JsonOpLog(this.name);
  final String name;

  Future<File> _logFile() async {
    final dir = await AtomicJsonStore._baseDir();
    final d = Directory(p.join(dir.path, '_oplogs'));
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return File(p.join(d.path, '${AtomicJsonStore._safeName(name)}.log'));
  }

  int? _lastIdCache;

  Future<int> _lastId() async {
    if (_lastIdCache != null) return _lastIdCache!;
    final f = await _logFile();
    if (!await f.exists()) return _lastIdCache = 0;

    try {
      final lines = await f.readAsLines();
      for (var i = lines.length - 1; i >= 0; i--) {
        final l = lines[i].trim();
        if (l.isEmpty) continue;
        try {
          final obj = jsonDecode(l);
          if (obj is Map) {
            final id = (obj['id'] as num?)?.toInt();
            if (id != null) return _lastIdCache = id;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return _lastIdCache = 0;
  }

  Future<void> append(String type, Map<String, dynamic> payload) {
    return _IoQueue.run('oplog:$name', () async {
      final f = await _logFile();
      final id = (await _lastId()) + 1;
      _lastIdCache = id;

      final map = <String, dynamic>{
        'id': id,
        'ts': DateTime.now().toIso8601String(),
        'type': type,
        'payload': payload,
      };
      final line = '${jsonEncode(map)}\n';
      await f.writeAsString(line, mode: FileMode.append, flush: true);
    });
  }

  Future<List<Map<String, dynamic>>> readAll() async {
    final f = await _logFile();
    if (!await f.exists()) return <Map<String, dynamic>>[];
    final lines = await f.readAsLines();
    final out = <Map<String, dynamic>>[];
    for (final l in lines) {
      final s = l.trim();
      if (s.isEmpty) continue;
      try {
        final obj = jsonDecode(s);
        if (obj is Map) out.add(Map<String, dynamic>.from(obj));
      } catch (_) {}
    }
    out.sort((a, b) => ((a['id'] as num?) ?? 0).compareTo(((b['id'] as num?) ?? 0)));
    _lastIdCache = out.isEmpty ? 0 : (out.last['id'] as num).toInt();
    return out;
  }

  /// Elimina todos los eventos con id <= [idInclusive].
  Future<void> truncateAfter(int idInclusive) {
    return _IoQueue.run('oplog:$name', () async {
      final f = await _logFile();
      if (!await f.exists()) return;
      final lines = await f.readAsLines();
      final keep = <String>[];
      for (final l in lines) {
        try {
          final obj = jsonDecode(l);
          if (obj is Map) {
            final id = (obj['id'] as num?)?.toInt() ?? -1;
            if (id > idInclusive) keep.add(l);
          }
        } catch (_) {}
      }
      final content = keep.isEmpty ? '' : '${keep.join('\n')}\n';
      await f.writeAsString(content, flush: true);

      if (keep.isEmpty) {
        _lastIdCache = 0;
      } else {
        try {
          final last = jsonDecode(keep.last);
          if (last is Map) {
            _lastIdCache = (last['id'] as num).toInt();
          } else {
            _lastIdCache = 0;
          }
        } catch (_) {
          _lastIdCache = 0;
        }
      }
    });
  }

  Future<void> capByEvents({required int maxEvents}) {
    return _IoQueue.run('oplog:$name', () async {
      final f = await _logFile();
      if (!await f.exists()) return;
      final lines = await f.readAsLines();
      if (lines.length <= maxEvents) return;

      final keep = lines.sublist(lines.length - maxEvents);
      await f.writeAsString('${keep.join('\n')}\n', flush: true);

      try {
        final last = jsonDecode(keep.last);
        if (last is Map) {
          _lastIdCache = (last['id'] as num).toInt();
        } else {
          _lastIdCache = null;
        }
      } catch (_) {
        _lastIdCache = null;
      }
    });
  }

  Future<void> capByBytes({required int maxBytes}) {
    return _IoQueue.run('oplog:$name', () async {
      final f = await _logFile();
      if (!await f.exists()) return;
      final stat = await f.stat();
      if (stat.size <= maxBytes) return;

      final lines = await f.readAsLines();
      final keep = lines.sublist((lines.length / 2).floor());
      await f.writeAsString('${keep.join('\n')}\n', flush: true);

      try {
        final last = jsonDecode(keep.last);
        if (last is Map) {
          _lastIdCache = (last['id'] as num).toInt();
        } else {
          _lastIdCache = null;
        }
      } catch (_) {
        _lastIdCache = null;
      }
    });
  }
}

class _FStat {
  final File file;
  final DateTime mtime;
  final int size;
  _FStat({required this.file, required this.mtime, required this.size});
}
