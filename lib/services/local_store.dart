// lib/services/local_store.dart — backend local blindado (cifrado + atómico)
// AES-GCM 256, escritura atómica, snapshots/índice cifrados, LRU, sin trunca.
// Fallback keyfile local (Random.secure) — sin flutter_secure_storage.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// ===== Modelos =====
class SheetData {
  final String sheetId;
  final String title;
  final List<String> headers;
  final List<RowData> rows;
  final DateTime updatedAt;

  SheetData({
    required this.sheetId,
    required this.title,
    required this.headers,
    required this.rows,
    DateTime? updatedAt,
  }) : updatedAt = (updatedAt ?? DateTime.now()).toUtc();

  Map<String, dynamic> toJson() => {
    'v': 2,
    'sheetId': sheetId,
    'title': title,
    'headers': headers,
    'rows': rows.map((e) => e.toJson()).toList(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory SheetData.fromJson(Map<String, dynamic> j) => SheetData(
    sheetId: (j['sheetId'] ?? '').toString(),
    title: (j['title'] ?? 'Bitácora').toString(),
    headers: (j['headers'] as List? ?? const <dynamic>[])
        .map((e) => (e ?? '').toString())
        .toList(),
    rows: (j['rows'] as List? ?? const <dynamic>[])
        .map((e) => RowData.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
    updatedAt:
    DateTime.tryParse((j['updatedAt'] ?? '').toString())?.toUtc() ??
        DateTime.now().toUtc(),
  );

  SheetData copyWith({
    String? title,
    List<String>? headers,
    List<RowData>? rows,
    DateTime? updatedAt,
  }) =>
      SheetData(
        sheetId: sheetId,
        title: title ?? this.title,
        headers: headers ?? this.headers,
        rows: rows ?? this.rows,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class RowData {
  final List<String> cells;
  final List<String> photos;
  final double? lat;
  final double? lng;

  RowData({
    required this.cells,
    List<String>? photos,
    this.lat,
    this.lng,
  }) : photos = photos ?? const <String>[];

  Map<String, dynamic> toJson() => {
    'cells': cells,
    'photos': photos,
    'lat': lat,
    'lng': lng,
  };

  factory RowData.fromJson(Map<String, dynamic> j) => RowData(
    cells: (j['cells'] as List? ?? const <dynamic>[])
        .map((e) => (e ?? '').toString())
        .toList(),
    photos: (j['photos'] as List? ?? const <dynamic>[])
        .map((e) => (e ?? '').toString())
        .toList(),
    lat: (j['lat'] is num) ? (j['lat'] as num).toDouble() : null,
    lng: (j['lng'] is num) ? (j['lng'] as num).toDouble() : null,
  );
}

class SheetSummary {
  final String sheetId;
  final String title;
  final DateTime updatedAt;
  final int headers;
  final int rows;
  final int photos;

  const SheetSummary({
    required this.sheetId,
    required this.title,
    required this.updatedAt,
    required this.headers,
    required this.rows,
    required this.photos,
  });

  Map<String, dynamic> toJson() => {
    'sheetId': sheetId,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
    'headers': headers,
    'rows': rows,
    'photos': photos,
  };

  factory SheetSummary.fromJson(Map<String, dynamic> j) => SheetSummary(
    sheetId: (j['sheetId'] ?? '').toString(),
    title: (j['title'] ?? 'Bitácora').toString(),
    updatedAt:
    DateTime.tryParse((j['updatedAt'] ?? '').toString())?.toUtc() ??
        DateTime.now().toUtc(),
    headers: (j['headers'] as num?)?.toInt() ?? 0,
    rows: (j['rows'] as num?)?.toInt() ?? 0,
    photos: (j['photos'] as num?)?.toInt() ?? 0,
  );
}

/// ===== Cripto util (keyfile local) =====
class _Crypto {
  static const _kAlgo = 'aes-gcm-256';
  static final _algo = AesGcm.with256bits();

  static Future<File> _keyFile() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'bitacora', 'keystore'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return File(p.join(dir.path, 'key.bin'));
  }

  static List<int> _randomBytes(int n) {
    final r = math.Random.secure();
    return List<int>.generate(n, (_) => r.nextInt(256));
  }

  static Future<SecretKey> _loadOrCreateKey() async {
    final f = await _keyFile();
    if (await f.exists()) {
      final kb = await f.readAsBytes();
      if (kb.length == 32) return SecretKey(kb);
    }
    final kb = _randomBytes(32);
    await f.writeAsBytes(kb, flush: true);
    return SecretKey(kb);
  }

  static Future<List<int>> encryptJson(Object payload) async {
    final key = await _loadOrCreateKey();
    final nonce = _randomBytes(12);
    final clear = utf8.encode(jsonEncode(payload));
    final box = await _algo.encrypt(clear, secretKey: key, nonce: nonce);
    final wrapper = {
      'enc_v': 1,
      'algo': _kAlgo,
      'n': base64Encode(nonce),
      'c': base64Encode(box.cipherText),
      't': base64Encode(box.mac.bytes),
    };
    return utf8.encode(jsonEncode(wrapper));
  }

  static Future<dynamic> decryptJson(List<int> bytes) async {
    try {
      final j = jsonDecode(utf8.decode(bytes));
      if (j is! Map) return null;
      final m = j.cast<String, dynamic>();
      if ((m['enc_v'] as num?)?.toInt() != 1 || m['algo'] != _kAlgo) {
        return null; // no es wrapper cifrado
      }
      final key = await _loadOrCreateKey();
      final box = SecretBox(
        base64Decode(m['c'] as String),
        nonce: base64Decode(m['n'] as String),
        mac: Mac(base64Decode(m['t'] as String)),
      );
      final clear = await _algo.decrypt(box, secretKey: key);
      return jsonDecode(utf8.decode(clear));
    } catch (_) {
      return null;
    }
  }

  static dynamic tryParseClear(List<int> bytes) {
    try {
      return jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return null;
    }
  }
}

/// ===== LocalStore (resiliente + LRU + snapshots + índice + cifrado) =====
class LocalStore {
  static final LocalStore I = LocalStore._();
  LocalStore._();

  static const int _snapshotsToKeep = 12;
  static const int _memMax = 10;
  static const String _indexFileName = 'sheets_index.json';

  void _log(Object msg, [Object? e, StackTrace? st]) {
    assert(() {
      debugPrint('[LocalStore] $msg ${e ?? ''}');
      if (st != null) debugPrint('$st');
      return true;
    }());
  }

  Future<Directory> _root() async {
    final Directory base = Platform.isWindows
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'bitacora', 'sheets'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<File> _fileFor(String sheetId) async {
    final dir = await _root();
    return File(p.join(dir.path, '$sheetId.json'));
  }

  Future<Directory> _snapDirFor(String sheetId) async {
    final dir = await _root();
    final snap = Directory(p.join(dir.path, '_snapshots', sheetId));
    if (!snap.existsSync()) snap.createSync(recursive: true);
    return snap;
  }

  Future<File> _indexFile() async {
    final dir = await _root();
    return File(p.join(dir.path, _indexFileName));
  }

  final LinkedHashMap<String, SheetData> _mem =
  LinkedHashMap<String, SheetData>();
  final Map<String, String> _lastPayloadStr = <String, String>{};

  void _cacheTouch(String id) {
    final v = _mem.remove(id);
    if (v != null) _mem[id] = v;
  }

  void _cachePut(String id, SheetData d, {String? payloadStr}) {
    _mem[id] = d;
    if (_mem.length > _memMax) {
      _mem.remove(_mem.keys.first);
    }
    if (payloadStr != null) _lastPayloadStr[id] = payloadStr;
  }

  final Map<String, Future<void>> _tails = <String, Future<void>>{};
  static const String _indexKey = '__index__';

  Future<T> _enqueue<T>(String key, Future<T> Function() task) {
    final Future<void> prev = _tails[key] ?? Future<void>.value();
    final c = Completer<T>();
    final chain = prev
        .then<T>((_) => task())
        .then<void>(c.complete, onError: (Object e, StackTrace st) {
      c.completeError(e, st);
    }).whenComplete(() {
      _tails.remove(key);
    });
    _tails[key] = chain;
    return c.future;
  }

  /// Write-atómico con rollback: escribe .tmp, renombra main->.bak, .tmp->main, borra .bak.
  Future<void> _writeAtomic(File target, List<int> bytes) async {
    final tmp = File('${target.path}.tmp');
    final bak = File('${target.path}.bak');

    // 1) Escribir tmp y flush
    final raf = await tmp.open(mode: FileMode.write);
    try {
      await raf.writeFrom(bytes);
      await raf.flush();
    } finally {
      await raf.close();
    }

    // 2) Renombrar existente a .bak (si hay)
    bool bakMade = false;
    if (await target.exists()) {
      try {
        if (await bak.exists()) {
          try {
            await bak.delete();
          } catch (_) {}
        }
        await target.rename(bak.path);
        bakMade = true;
      } catch (e, st) {
        _log('backup rename failed', e, st);
        // Si no se pudo hacer .bak, borramos main como último recurso.
        try {
          await target.delete();
        } catch (_) {}
      }
    }

    // 3) Promover tmp -> main
    try {
      await tmp.rename(target.path);
    } catch (e, st) {
      _log('promote tmp->main failed, trying rollback', e, st);
      // Si falló, intentar restaurar .bak
      try {
        if (await bak.exists()) {
          await bak.rename(target.path);
        }
      } catch (e2, st2) {
        _log('rollback failed', e2, st2);
      }
      rethrow;
    }

    // 4) Borrar .bak si quedó
    if (bakMade) {
      try {
        if (await bak.exists()) {
          await bak.delete();
        }
      } catch (e, st) {
        _log('delete .bak failed', e, st);
      }
    }
  }

  /// Intenta recuperar de .tmp/.bak si el main falta o está corrupto.
  Future<void> _recoverIfNeeded(File mainFile) async {
    final tmp = File('${mainFile.path}.tmp');
    final bak = File('${mainFile.path}.bak');

    // Si no hay main pero hay tmp -> promover
    if (!await mainFile.exists() && await tmp.exists()) {
      try {
        await tmp.rename(mainFile.path);
      } catch (e, st) {
        _log('promote tmp during recover failed', e, st);
      }
    }

    // Si sigue sin main y hay bak -> restaurar
    if (!await mainFile.exists() && await bak.exists()) {
      try {
        await bak.rename(mainFile.path);
      } catch (e, st) {
        _log('restore bak during recover failed', e, st);
      }
    }

    // Limpiar restos viejos si ya hay main
    if (await mainFile.exists()) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      try {
        if (await bak.exists()) await bak.delete();
      } catch (_) {}
    }
  }

  Future<void> _writeSnapshot(String sheetId, List<int> encBytes) async {
    try {
      final dir = await _snapDirFor(sheetId);
      final ts =
      DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.\-]'), '');
      final f = File(p.join(dir.path, '$sheetId-$ts.json'));
      await f.writeAsBytes(encBytes, flush: true);

      final entries = <File, DateTime>{};
      await for (final e in dir.list()) {
        if (e is File && e.path.endsWith('.json')) {
          try {
            entries[e] = await e.lastModified();
          } catch (_) {}
        }
      }
      final sorted = entries.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (var i = _snapshotsToKeep; i < sorted.length; i++) {
        try {
          await sorted[i].key.delete();
        } catch (e, st) {
          _log('snapshot trim failed', e, st);
        }
      }
    } catch (e, st) {
      _log('writeSnapshot failed', e, st);
    }
  }

  Future<Map<String, dynamic>?> _readLatestSnapshotDecrypted(
      String sheetId) async {
    try {
      final dir = await _snapDirFor(sheetId);
      final files = <File, DateTime>{};
      await for (final e in dir.list()) {
        if (e is File && e.path.endsWith('.json')) {
          try {
            files[e] = await e.lastModified();
          } catch (_) {}
        }
      }
      if (files.isEmpty) return null;
      final newest = files.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final entry in newest) {
        try {
          final raw = await entry.key.readAsBytes();
          final dec =
              await _Crypto.decryptJson(raw) ?? _Crypto.tryParseClear(raw);
          if (dec is Map<String, dynamic>) {
            final sid = (dec['sheetId'] ?? '').toString();
            if (sid == sheetId) return dec;
          }
        } catch (_) {}
      }
    } catch (e, st) {
      _log('readLatestSnapshot failed', e, st);
    }
    return null;
  }

  Future<List<SheetSummary>?> _readIndexRaw() async {
    try {
      final f = await _indexFile();
      if (await f.exists()) {
        final raw = await f.readAsBytes();
        final j = await _Crypto.decryptJson(raw) ?? _Crypto.tryParseClear(raw);
        if (j is List) {
          return (j)
              .whereType<Map<String, dynamic>>()
              .map(SheetSummary.fromJson)
              .toList();
        }
      }
    } catch (e, st) {
      _log('readIndexRaw failed', e, st);
    }
    return null;
  }

  Future<List<SheetSummary>> _rebuildIndexFromDisk() async {
    final dir = await _root();
    final out = <SheetSummary>[];
    await for (final e in dir.list()) {
      if (e is! File) continue;
      if (!e.path.endsWith('.json')) continue;
      if (p.basename(e.path) == _indexFileName) continue;
      try {
        final raw = await e.readAsBytes();
        final j = await _Crypto.decryptJson(raw) ?? _Crypto.tryParseClear(raw);
        if (j is Map<String, dynamic>) {
          final d = SheetData.fromJson(j);
          out.add(SheetSummary(
            sheetId: d.sheetId,
            title: d.title,
            updatedAt: d.updatedAt,
            headers: d.headers.length,
            rows: d.rows.length,
            photos: d.rows.fold<int>(0, (a, r) => a + r.photos.length),
          ));
        }
      } catch (_) {}
    }
    try {
      final idxFile = await _indexFile();
      final enc =
      await _Crypto.encryptJson(out.map((e) => e.toJson()).toList());
      await _writeAtomic(idxFile, enc);
    } catch (_) {}
    return out;
  }

  Future<List<SheetSummary>> _readIndex() async {
    final raw = await _readIndexRaw();
    if (raw != null) return raw;
    return _rebuildIndexFromDisk();
  }

  Future<void> _updateIndexFromData(SheetData d) async {
    await _enqueue<void>(_indexKey, () async {
      final list = await _readIndex();
      final photosCount =
      d.rows.fold<int>(0, (a, r) => a + r.photos.length);
      final sum = SheetSummary(
        sheetId: d.sheetId,
        title: d.title,
        updatedAt: d.updatedAt,
        headers: d.headers.length,
        rows: d.rows.length,
        photos: photosCount,
      );
      final i = list.indexWhere((e) => e.sheetId == d.sheetId);
      if (i >= 0) {
        list[i] = sum;
      } else {
        list.add(sum);
      }
      final idxFile = await _indexFile();
      final enc =
      await _Crypto.encryptJson(list.map((e) => e.toJson()).toList());
      await _writeAtomic(idxFile, enc);
    });
  }

  Future<void> _removeFromIndex(String sheetId) async {
    await _enqueue<void>(_indexKey, () async {
      final list = await _readIndex();
      list.removeWhere((e) => e.sheetId == sheetId);
      final idxFile = await _indexFile();
      final enc =
      await _Crypto.encryptJson(list.map((e) => e.toJson()).toList());
      await _writeAtomic(idxFile, enc);
    });
  }

  Future<List<SheetSummary>> listSummaries() async {
    return _readIndex();
  }

  // === Consistencia sin pérdidas ===
  SheetData _normalize(SheetData d) {
    final cols = d.headers.length;
    if (cols <= 0) return d;
    final rows = <RowData>[];
    for (final r in d.rows) {
      final cells = List<String>.from(r.cells);
      if (cells.length < cols) {
        cells.addAll(List.filled(cols - cells.length, ''));
      }
      rows.add(RowData(
        cells: cells,
        photos: List<String>.from(r.photos),
        lat: r.lat,
        lng: r.lng,
      ));
    }
    return d.copyWith(rows: rows);
  }

  String _payloadString(SheetData d) {
    final n = _normalize(d);
    final map = n.toJson()..remove('updatedAt');
    return jsonEncode(map);
  }

  Future<void> save(SheetData data) async {
    await _enqueue<void>(data.sheetId, () async {
      final stamped = data.copyWith(updatedAt: DateTime.now().toUtc());
      final norm = _normalize(stamped);
      final payloadStr = _payloadString(norm);
      final last = _lastPayloadStr[data.sheetId];
      if (last == payloadStr) {
        await _updateIndexFromData(norm);
        _cachePut(norm.sheetId, norm);
        return;
      }

      final f = await _fileFor(norm.sheetId);
      final enc = await _Crypto.encryptJson(norm.toJson());
      await _writeAtomic(f, enc);
      unawaited(_writeSnapshot(norm.sheetId, enc));
      await _updateIndexFromData(norm);
      _cachePut(norm.sheetId, norm, payloadStr: payloadStr);
    });
  }

  Future<SheetData?> load(String sheetId) async {
    return _enqueue<SheetData?>(sheetId, () async {
      final cached = _mem[sheetId];
      if (cached != null) {
        _cacheTouch(sheetId);
        return cached;
      }

      final f = await _fileFor(sheetId);
      await _recoverIfNeeded(f);

      Map<String, dynamic>? j;
      if (await f.exists()) {
        try {
          final raw = await f.readAsBytes();
          final dec =
              await _Crypto.decryptJson(raw) ?? _Crypto.tryParseClear(raw);
          if (dec is Map<String, dynamic> &&
              (dec['sheetId'] ?? '').toString() == sheetId) {
            j = dec;
          }
        } catch (e, st) {
          _log('main read failed, trying snapshot: ${f.path}', e, st);
        }
      }
      j ??= await _readLatestSnapshotDecrypted(sheetId);
      if (j == null) return null;

      final d = _normalize(SheetData.fromJson(j));
      _cachePut(sheetId, d, payloadStr: _payloadString(d));
      await _updateIndexFromData(d);
      return d;
    });
  }

  Future<void> delete(String sheetId) async {
    await _enqueue<void>(sheetId, () async {
      _mem.remove(sheetId);
      _lastPayloadStr.remove(sheetId);

      final f = await _fileFor(sheetId);
      final tmp = File('${f.path}.tmp');
      final bak = File('${f.path}.bak');

      try {
        if (await f.exists()) await f.delete();
      } catch (e, st) {
        _log('delete main failed: ${f.path}', e, st);
      }
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (e, st) {
        _log('delete tmp failed: ${tmp.path}', e, st);
      }
      try {
        if (await bak.exists()) await bak.delete();
      } catch (e, st) {
        _log('delete bak failed: ${bak.path}', e, st);
      }
      try {
        final snapDir = await _snapDirFor(sheetId);
        if (await snapDir.exists()) {
          await snapDir.delete(recursive: true);
        }
      } catch (e, st) {
        _log('delete snapshots failed', e, st);
      }
      await _removeFromIndex(sheetId);
    });
  }
}
