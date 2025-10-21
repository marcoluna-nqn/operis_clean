// ==========================
// lib/services/crash_guard.dart
// ==========================
// CrashGuard: estado de sesión resiliente con snapshots atómicos,
// OpLog compacto, cola de escritura, barrido periódico y utilidades
// de depuración. 100% local y sin fugas.

import 'dart:async' show Timer, unawaited;
import 'dart:convert' show jsonEncode;
import 'dart:isolate';
import 'dart:io';
import 'dart:ui' as ui show PlatformDispatcher;

import 'package:flutter/foundation.dart' show FlutterError, FlutterErrorDetails, kDebugMode;
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'durable_store.dart';

/// ===== Modelo de estado =====
class SheetSessionState {
  final String? sheetId;
  final double scrollOffset;
  /// Borrador: clave "rowId:colKey" -> valor
  final Map<String, String> draft;
  /// Fotos fsync‑eadas aún no linkeadas (rehidratación segura)
  final List<String> photoPaths;
  final DateTime updatedAt;

  const SheetSessionState({
    required this.sheetId,
    required this.scrollOffset,
    required this.draft,
    required this.photoPaths,
    required this.updatedAt,
  });

  SheetSessionState copyWith({
    String? sheetId,
    double? scrollOffset,
    Map<String, String>? draft,
    List<String>? photoPaths,
    DateTime? updatedAt,
  }) => SheetSessionState(
    sheetId: sheetId ?? this.sheetId,
    scrollOffset: scrollOffset ?? this.scrollOffset,
    draft: draft ?? this.draft,
    photoPaths: photoPaths ?? this.photoPaths,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'sheetId': sheetId,
    'scrollOffset': scrollOffset,
    'draft': draft,
    'photoPaths': photoPaths,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory SheetSessionState.fromJson(Map<String, dynamic> j) => SheetSessionState(
    sheetId: j['sheetId'] as String?,
    scrollOffset: (j['scrollOffset'] is num) ? (j['scrollOffset'] as num).toDouble() : 0.0,
    draft: (j['draft'] is Map)
        ? (j['draft'] as Map).map((k, v) => MapEntry('$k', '$v')).cast<String, String>()
        : <String, String>{},
    photoPaths: (j['photoPaths'] is List)
        ? (j['photoPaths'] as List).map((e) => '$e').toList()
        : <String>[],
    updatedAt: DateTime.tryParse('${j['updatedAt'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  static SheetSessionState empty() => SheetSessionState(
    sheetId: null,
    scrollOffset: 0,
    draft: <String, String>{},
    photoPaths: <String>[],
    updatedAt: DateTime.now(),
  );
}

/// ===== CrashGuard =====
class CrashGuard {
  CrashGuard._();
  static final CrashGuard I = CrashGuard._();

  static const String _kStateFile = 'last_session_state';
  static const String _kOpLogName = 'session_ops';

  // Tiempos
  static const Duration _debounceDur = Duration(milliseconds: 500);
  static const Duration _maxFlushInterval = Duration(seconds: 5); // flush garantizado ≤ 5s
  static const int _oplogMaxEvents = 20000;

  final JsonOpLog _log = JsonOpLog(_kOpLogName); // compatible con tu durable_store

  SheetSessionState _state = SheetSessionState.empty();

  Timer? _debounce;
  Timer? _sweeper;
  DateTime _lastFlushAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Firma del último snapshot persistido (para evitar I/O redundante).
  String? _lastSig;

  // Hooks
  _LifecycleFlushObserver? _lifecycleObs;
  bool _hooksInstalled = false;

  // Métricas (debug)
  int _replayApplied = 0, _replayIgnored = 0, _replayCorrupt = 0;

  /// Init idempotente: estado resiliente + replay del OpLog + barrido periódico.
  Future<void> init() async {
    final Map<String, dynamic> j = await AtomicJsonStore.readResilient(_kStateFile);
    _state = j.isEmpty ? SheetSessionState.empty() : SheetSessionState.fromJson(j);
    _lastSig = _coreSig();
    await _replayOpLog();
    _startSweeper();
  }

  /// Setup recomendado: init + hooks + flush al pausar.
  Future<void> ensureInstalled() async {
    await init();
    hookPlatformErrors();
    enableAutoFlushOnPause();
  }

  /// Limpia hooks y timers.
  Future<void> dispose() async {
    disableAutoFlushOnPause();
    _stopSweeper();
    await flushNow();
  }

  /// Snapshot actual.
  SheetSessionState current() => _state;

  /// Instala hooks globales de errores + flush en background.
  void hookPlatformErrors() {
    if (_hooksInstalled) return;
    _hooksInstalled = true;

    FlutterError.onError = (FlutterErrorDetails details) async {
      FlutterError.presentError(details);
      unawaited(_log.append('flutter_error', {
        'sheetId': _state.sheetId,
        'exception': '${details.exception}',
        'stack': '${details.stack}',
      }));
      await flushNow();
    };

    ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      unawaited(_log.append('platform_error', {
        'sheetId': _state.sheetId,
        'error': '$error',
        'stack': '$stack',
      }));
      unawaited(flushNow());
      return true;
    };

    Isolate.current.addErrorListener(
      RawReceivePort((dynamic _) async { await flushNow(); }).sendPort,
    );
  }

  /// Flush al pausar.
  void enableAutoFlushOnPause() {
    _lifecycleObs ??= _LifecycleFlushObserver(onSuspend: flushNow);
    WidgetsBinding.instance.addObserver(_lifecycleObs!);
  }

  void disableAutoFlushOnPause() {
    final obs = _lifecycleObs;
    if (obs != null) {
      WidgetsBinding.instance.removeObserver(obs);
      _lifecycleObs = null;
    }
  }

  /// Cambia la planilla activa.
  void setCurrentSheet(String sheetId) {
    final String safeId = _sanitizeId(sheetId);
    if (_state.sheetId != safeId) {
      _state = _state.copyWith(
        sheetId: safeId,
        scrollOffset: 0.0,
        draft: <String, String>{},
        photoPaths: <String>[],
        updatedAt: DateTime.now(),
      );
    } else {
      _state = _state.copyWith(sheetId: safeId, updatedAt: DateTime.now());
    }
    _scheduleFlush();
    unawaited(_log.append('sheet_open', {'sheetId': safeId}));
  }

  /// Edit de celda en borrador.
  void recordCellEdit({
    required Object rowId,
    required String colKey,
    required String value,
  }) {
    final String k = '${_sanitizeId(rowId.toString())}:${_sanitizeKey(colKey)}';
    final nextDraft = Map<String, String>.from(_state.draft)..[k] = value;
    _state = _state.copyWith(draft: nextDraft, updatedAt: DateTime.now());
    _scheduleFlush();
    unawaited(_log.append('cell_edit', {'k': k, 'v': value, 'sheetId': _state.sheetId}));
  }

  /// Confirmación de persistencia fuerte (borra del borrador).
  void confirmCellPersisted({required Object rowId, required String colKey}) {
    final String k = '${_sanitizeId(rowId.toString())}:${_sanitizeKey(colKey)}';
    if (_state.draft.containsKey(k)) {
      final next = Map<String, String>.from(_state.draft)..remove(k);
      _state = _state.copyWith(draft: next, updatedAt: DateTime.now());
      _scheduleFlush();
    }
    unawaited(_log.append('cell_persisted', {'k': k, 'sheetId': _state.sheetId}));
  }

  /// Limpia todo el borrador.
  void clearDraftForCurrentSheet() {
    if (_state.draft.isEmpty) return;
    _state = _state.copyWith(draft: <String, String>{}, updatedAt: DateTime.now());
    _scheduleFlush();
    unawaited(_log.append('draft_cleared', {'sheetId': _state.sheetId}));
  }

  /// Guarda desplazamiento.
  void recordScrollOffset(double offset) {
    _state = _state.copyWith(scrollOffset: offset, updatedAt: DateTime.now());
    _scheduleFlush();
    unawaited(_log.append('scroll', {'y': offset, 'sheetId': _state.sheetId}));
  }

  /// Copia una foto a AppSupport con fsync y la deja pendiente de vincular.
  Future<String> persistPhotoSafely(
      File src, {
        required String sheetId,
        required Object rowId,
      }) async {
    final String safeSheet = _sanitizeId(sheetId);
    final String safeRow = _sanitizeId(rowId.toString());

    final base = await _appSupportBitacora();
    final dir = Directory(p.join(base.path, 'photos', safeSheet, safeRow));
    if (!await dir.exists()) await dir.create(recursive: true);

    final String name = 'IMG_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final File dst = File(p.join(dir.path, name));
    final File tmp = File('${dst.path}.part');

    // Lee bytes en Isolate.
    final String srcPath = src.path;
    final List<int> bytes = await Isolate.run(() => File(srcPath).readAsBytesSync());

    // Escritura atómica: temp + flush + rename.
    final raf = await tmp.open(mode: FileMode.write);
    try {
      await raf.writeFrom(bytes);
      await raf.flush();
    } finally {
      await raf.close();
    }
    await tmp.rename(dst.path);

    final nextPhotos = List<String>.from(_state.photoPaths)..add(dst.path);
    _state = _state.copyWith(photoPaths: nextPhotos, updatedAt: DateTime.now());

    await AtomicJsonStore.writeAtomicWithSnapshots(_kStateFile, _state.toJson(), keep: 12);
    _lastSig = _coreSig();

    await _log.append('photo_persisted', {
      'path': dst.path,
      'sheetId': safeSheet,
      'rowId': safeRow,
    });

    return dst.path;
  }

  /// Si la cámara ya guardó el archivo, solo registralo.
  void stagePhotoPath(String path) {
    final f = File(path);
    if (!f.existsSync()) return;
    if (_state.photoPaths.contains(path)) return;
    final next = List<String>.from(_state.photoPaths)..add(path);
    _state = _state.copyWith(photoPaths: next, updatedAt: DateTime.now());
    _scheduleFlush();
    unawaited(_log.append('photo_staged', {'path': path, 'sheetId': _state.sheetId}));
  }

  /// Confirma que la foto ya está vinculada en el modelo.
  void confirmPhotoLinked(String path) {
    if (_state.photoPaths.contains(path)) {
      final next = List<String>.from(_state.photoPaths)..remove(path);
      _state = _state.copyWith(photoPaths: next, updatedAt: DateTime.now());
      _scheduleFlush();
    }
    unawaited(_log.append('photo_linked', {'path': path, 'sheetId': _state.sheetId}));
  }

  /// Fuerza escritura inmediata (No‑Op si no cambió).
  Future<void> flushNow() async {
    _debounce?.cancel();
    final sig = _coreSig();
    if (sig == _lastSig) return;
    await AtomicJsonStore.writeAtomicWithSnapshots(_kStateFile, _state.toJson(), keep: 12);
    _lastSig = sig;
    _lastFlushAt = DateTime.now();
  }

  /// Limpia todo el estado.
  Future<void> clear() async {
    _debounce?.cancel();
    _state = SheetSessionState.empty();
    await AtomicJsonStore.writeAtomicWithSnapshots(_kStateFile, _state.toJson(), keep: 12);
    _lastSig = _coreSig();
    _lastFlushAt = DateTime.now();
  }

  /// Exporta bundle de debug local.
  Future<File> exportDebugBundle() async {
    final base = await _appSupportBitacora();
    final dir = Directory(p.join(base.path, 'debug'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final stamp = _stamp();
    final f = File(p.join(dir.path, 'bitacora_debug_$stamp.txt'));

    // Listado de snapshots del estado
    final snapsDir = Directory(p.join(base.path, '_snapshots', _kStateFile));
    final snaps = <String>[];
    if (snapsDir.existsSync()) {
      for (final e in snapsDir.listSync()) {
        if (e is File && e.path.endsWith('.json')) snaps.add(e.path);
      }
      // ordenar descendente sin usar reverse()
      snaps.sort((a, b) => b.compareTo(a));
    }

    final content = StringBuffer()
      ..writeln('CrashGuard Debug — $stamp')
      ..writeln('appSupport: ${base.path}')
      ..writeln('state:')
      ..writeln(jsonEncode(_state.toJson()))
      ..writeln('coreSig: ${_coreSig()}')
      ..writeln('snapshots:')
      ..writeln(snaps.join('\n'));
    await f.writeAsString(content.toString(), flush: true);
    return f;
  }

  // ----- internos -----

  void _startSweeper() {
    _sweeper ??= Timer.periodic(const Duration(seconds: 2), (_) async {
      final since = DateTime.now().difference(_lastFlushAt);
      if (since >= _maxFlushInterval) {
        await flushNow();
      }
    });
  }

  void _stopSweeper() {
    _sweeper?.cancel();
    _sweeper = null;
  }

  void _scheduleFlush() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDur, () async {
      final sig = _coreSig();
      if (sig == _lastSig) return;
      await AtomicJsonStore.writeAtomicWithSnapshots(_kStateFile, _state.toJson(), keep: 12);
      _lastSig = sig;
      _lastFlushAt = DateTime.now();
    });
  }

  Future<void> _replayOpLog() async {
    final List<Map<String, dynamic>> events = await _log.readAll();
    if (events.isEmpty) return;

    final Map<String, String> draft = Map<String, String>.from(_state.draft);
    final List<String> photos = List<String>.from(_state.photoPaths);

    int lastAppliedAnyId = 0;
    int lastAppliedMutId = 0;
    String? currentSheet = _state.sheetId;
    _replayApplied = _replayIgnored = _replayCorrupt = 0;

    for (final Map<String, dynamic> e in events) {
      try {
        final int id = (e['id'] as num).toInt();
        final String type = '${e['type']}';
        final Map<String, dynamic> pl =
        (e['payload'] is Map) ? (e['payload'] as Map).cast<String, dynamic>() : const <String, dynamic>{};

        lastAppliedAnyId = id;

        if (type == 'sheet_open') {
          currentSheet = (pl['sheetId'] as String?) ?? currentSheet;
          _state = _state.copyWith(sheetId: currentSheet, updatedAt: DateTime.now());
          _replayApplied++; lastAppliedMutId = id; continue;
        }

        final String? evSheet = pl['sheetId'] as String?;
        if (evSheet == null || (currentSheet != null && evSheet != currentSheet)) {
          _replayIgnored++; continue;
        }

        switch (type) {
          case 'cell_edit':
            draft['${pl['k']}'] = '${pl['v']}';
            _replayApplied++; lastAppliedMutId = id; break;
          case 'cell_persisted':
            draft.remove('${pl['k']}');
            _replayApplied++; lastAppliedMutId = id; break;
          case 'draft_cleared':
            draft.clear();
            _replayApplied++; lastAppliedMutId = id; break;
          case 'scroll':
            _state = _state.copyWith(
              scrollOffset: (pl['y'] as num?)?.toDouble() ?? 0.0,
              updatedAt: DateTime.now(),
            );
            _replayApplied++; lastAppliedMutId = id; break;
          case 'photo_persisted':
          case 'photo_staged':
            final path = '${pl['path']}';
            if (!photos.contains(path)) photos.add(path);
            _replayApplied++; lastAppliedMutId = id; break;
          case 'photo_linked':
            photos.remove('${pl['path']}');
            _replayApplied++; lastAppliedMutId = id; break;
          default:
            _replayIgnored++; break;
        }
      } catch (e, st) {
        _replayCorrupt++;
        if (kDebugMode) {
          // ignore: avoid_print
          print('[CrashGuard] evento corrupto durante replay: $e\n$st');
        }
        continue;
      }
    }

    // Filtrar rutas inexistentes
    final filteredPhotos = <String>[
      for (final pth in photos) if (File(pth).existsSync()) pth,
    ];

    _state = _state.copyWith(
      draft: draft,
      photoPaths: filteredPhotos,
      updatedAt: DateTime.now(),
    );

    await AtomicJsonStore.writeAtomicWithSnapshots(_kStateFile, _state.toJson(), keep: 12);
    _lastSig = _coreSig();

    if (lastAppliedMutId > 0) await _log.truncateAfter(lastAppliedMutId);
    // Compat: durable_store sin compactIfNeeded -> solo limitar por eventos
    await _log.capByEvents(maxEvents: _oplogMaxEvents);

    if (kDebugMode) {
      // ignore: avoid_print
      print('[CrashGuard] replay => applied=$_replayApplied ignored=$_replayIgnored corrupt=$_replayCorrupt lastAny=$lastAppliedAnyId lastMut=$lastAppliedMutId');
    }
  }

  /// Firma estable (ignora updatedAt) para evitar escrituras redundantes.
  String _coreSig() => jsonEncode(<String, Object?>{
    'sheetId': _state.sheetId,
    'scroll': _state.scrollOffset,
    'draft': _state.draft,
    'photos': _state.photoPaths,
  });

  /// Sanitiza IDs para uso en disco.
  String _sanitizeId(String raw) {
    final sb = StringBuffer();
    for (final r in raw.runes) {
      final c = String.fromCharCode(r);
      final code = c.codeUnitAt(0);
      final ok = (code >= 48 && code <= 57) || // 0‑9
          (code >= 65 && code <= 90) || // A‑Z
          (code >= 97 && code <= 122) || // a‑z
          c == '-' || c == '_';
      sb.write(ok ? c : '_');
    }
    final s = sb.toString();
    return s.isEmpty ? 'unknown' : s;
  }

  /// Sanitiza claves de columna para el draft (e.g., "c0", "h2").
  String _sanitizeKey(String raw) => _sanitizeId(raw);

  // Paths
  Future<Directory> _appSupportBitacora() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory(p.join(root.path, 'bitacora'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }
}

/// ===== Lifecycle helper =====
class _LifecycleFlushObserver with WidgetsBindingObserver {
  _LifecycleFlushObserver({required this.onSuspend});
  final Future<void> Function() onSuspend;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(onSuspend());
    }
  }
}

/// Hook opcional: flush al suspender sin pasar BuildContext.
mixin CrashGuardLifecycle on Object {
  Future<void> onAppLifecycleWillSuspend() => CrashGuard.I.flushNow();
}
