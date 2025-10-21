// lib/services/upload_queue.dart
import 'dart:async'; // Timer, unawaited
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as imglib;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'media_paths.dart';
import 'photo_uploader.dart';
import 'durable_store.dart'; // AtomicJsonStore

enum UploadState { pending, uploading, verifying, done, failed }

typedef UploadHook = void Function(String event, UploadTask task, {Object? data});
typedef ConnectivityProbe = Future<bool> Function(bool wifiOnly);

class UploadTask {
  final String id;
  final String localPath;   // en tmp/ hasta “done”
  final String thumbPath;   // miniatura para UI
  final String sheetId;     // texto robusto
  final String rowKey;      // id estable de fila
  final int createdAt;      // epoch-ms
  final String sha256hex;   // integridad
  final UploadState state;
  final int retries;
  final String? remoteUrl;
  final String? lastError;
  final int? nextAttemptAt; // epoch-ms
  final int priority;       // mayor -> se procesa antes

  UploadTask({
    required this.id,
    required this.localPath,
    required this.thumbPath,
    required this.sheetId,
    required this.rowKey,
    required this.createdAt,
    required this.sha256hex,
    this.state = UploadState.pending,
    this.retries = 0,
    this.remoteUrl,
    this.lastError,
    this.nextAttemptAt,
    this.priority = 0,
  });

  UploadTask copy({
    String? id,
    String? localPath,
    String? thumbPath,
    String? sheetId,
    String? rowKey,
    int? createdAt,
    String? sha256hex,
    UploadState? state,
    int? retries,
    String? remoteUrl,
    String? lastError,
    int? nextAttemptAt,
    int? priority,
  }) {
    return UploadTask(
      id: id ?? this.id,
      localPath: localPath ?? this.localPath,
      thumbPath: thumbPath ?? this.thumbPath,
      sheetId: sheetId ?? this.sheetId,
      rowKey: rowKey ?? this.rowKey,
      createdAt: createdAt ?? this.createdAt,
      sha256hex: sha256hex ?? this.sha256hex,
      state: state ?? this.state,
      retries: retries ?? this.retries,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      lastError: lastError ?? this.lastError,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      priority: priority ?? this.priority,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'localPath': localPath,
    'thumbPath': thumbPath,
    'sheetId': sheetId,
    'rowKey': rowKey,
    'createdAt': createdAt,
    'sha256hex': sha256hex,
    'state': state.name,
    'retries': retries,
    'remoteUrl': remoteUrl,
    'lastError': lastError,
    'nextAttemptAt': nextAttemptAt,
    'priority': priority,
  };

  static UploadTask fromJson(Map<String, dynamic> j) => UploadTask(
    id: j['id'] as String,
    localPath: j['localPath'] as String,
    thumbPath: j['thumbPath'] as String,
    sheetId: j['sheetId'] as String,
    rowKey: j['rowKey'] as String,
    createdAt: j['createdAt'] as int,
    sha256hex: j['sha256hex'] as String,
    state: UploadState.values.firstWhere(
          (e) => e.name == j['state'],
      orElse: () => UploadState.pending,
    ),
    retries: (j['retries'] as int?) ?? 0,
    remoteUrl: j['remoteUrl'] as String?,
    lastError: j['lastError'] as String?,
    nextAttemptAt: j['nextAttemptAt'] as int?,
    priority: (j['priority'] as int?) ?? 0,
  );
}

class UploadQueue {
  UploadQueue({
    required this.uploader,
    this.maxParallel = 2,
    this.wifiOnly = false,
    this.hook,
    this.connectivityProbe,
  });

  final PhotoUploader uploader;
  final int maxParallel;
  final bool wifiOnly;
  final UploadHook? hook;
  final ConnectivityProbe? connectivityProbe;

  List<UploadTask> _tasks = [];
  bool _busy = false;
  int _prevSleepMs = 1000; // estado para backoff decorrelated-jitter (persistido)
  Timer? _wake;            // wake-up diferido para reintentos

  // ---------- persistencia JSON (atómica + snapshots) ----------
  static const _storeName = 'upload_queue';

  Future<void> _load() async {
    final j = await AtomicJsonStore.readResilient(_storeName);
    final rawList = (j['tasks'] as List?) ?? const <Object?>[];
    _tasks = rawList
        .map((e) => UploadTask.fromJson((e as Map).cast<String, dynamic>()))
        .toList();

    final ps = (j['prevSleepMs'] as num?)?.toInt();
    if (ps != null) {
      // sanea valores
      _prevSleepMs = ps.clamp(500, 21600 * 1000);
    }
  }

  Future<void> _save() async {
    await AtomicJsonStore.writeAtomicWithSnapshots(
      _storeName,
      {
        'tasks': _tasks.map((e) => e.toJson()).toList(),
        'prevSleepMs': _prevSleepMs,
      },
      keep: 8,
    );
  }

  Future<List<UploadTask>> all() async {
    await _load();
    return List.unmodifiable(_tasks);
  }

  // ---------- API pública ----------
  /// Prepara archivo (tmp + thumb + checksum) y encola.
  Future<UploadTask> enqueueFromCamera({
    required File captured,
    required String sheetId,
    required String rowKey,
    int priority = 0,
  }) async {
    await _load();
    final id = const Uuid().v4();

    // Copia a tmp/
    final ext = p.extension(captured.path).toLowerCase();
    final tmp = await MediaPaths.tmpFile('$id$ext');
    await captured.copy(tmp.path);

    // Normaliza (orientación jpeg) + genera thumb
    await _normalizeImageIfNeeded(tmp);
    final thumb = await MediaPaths.tmpFile('$id.thumb.jpg');
    await _genThumb(tmp, thumb, maxSide: 300);

    // Checksum
    final sha = await computeSha256(tmp);

    final t = UploadTask(
      id: id,
      localPath: tmp.path,
      thumbPath: thumb.path,
      sheetId: sheetId,
      rowKey: rowKey,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      sha256hex: sha,
      priority: priority,
    );

    _tasks.add(t);
    await _save();
    hook?.call('enqueue', t);

    // lanzar runner sin bloquear
    unawaited(_kick());
    return t;
  }

  /// Elimina una tarea de la cola (opcionalmente borra archivos).
  Future<bool> removeTask(String id, {bool deleteFiles = false}) async {
    await _load();
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i < 0) return false;
    final t = _tasks.removeAt(i);
    await _save();

    if (deleteFiles) {
      try {
        final lf = File(t.localPath);
        if (await lf.exists()) await lf.delete();
      } catch (_) {}
      try {
        final tf = File(t.thumbPath);
        if (await tf.exists()) await tf.delete();
      } catch (_) {}
    }
    hook?.call('remove', t);
    return true;
  }

  /// Limpieza/grooming.
  Future<void> groom({int maxTasks = 500}) async {
    await _load();
    final now = DateTime.now().millisecondsSinceEpoch;

    _tasks.removeWhere((t) {
      final isOldDone =
          t.state == UploadState.done && (now - t.createdAt) > 7 * 86400 * 1000;
      final isOldFailed = t.state == UploadState.failed &&
          t.retries > 8 &&
          (now - (t.nextAttemptAt ?? now)) > 7 * 86400 * 1000;
      return isOldDone || isOldFailed;
    });

    if (_tasks.length > maxTasks) {
      _tasks.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _tasks = _tasks.sublist(_tasks.length - maxTasks);
    }

    for (final t in _tasks) {
      try {
        final lf = File(t.localPath);
        if (!await lf.exists()) {
          final tf = File(t.thumbPath);
          if (await tf.exists()) await tf.delete();
        }
      } catch (_) {}
    }

    await _save();
    hook?.call(
      'groom',
      UploadTask(
        id: 'groom',
        localPath: '',
        thumbPath: '',
        sheetId: '',
        rowKey: '',
        createdAt: now,
        sha256hex: '',
      ),
    );
  }

  // ---------- Runner ----------
  void _armWake(Duration d) {
    _wake?.cancel();
    _wake = Timer(d, () {
      unawaited(_kick());
    });
  }

  Future<void> _kick() async {
    if (_busy) return;
    _busy = true;
    try {
      await _load();

      // Consciencia de red (inyectable)
      if (connectivityProbe != null) {
        final hasNet = await connectivityProbe!(wifiOnly);
        if (!hasNet) {
          _armWake(const Duration(minutes: 2));
          return;
        }
      }

      while (true) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final pendings = _tasks
            .where((t) =>
        (t.state == UploadState.pending ||
            t.state == UploadState.failed) &&
            (t.nextAttemptAt == null || t.nextAttemptAt! <= now))
            .toList()
          ..sort((a, b) {
            // prioridad desc, luego más antiguos primero
            final byPrio = b.priority.compareTo(a.priority);
            if (byPrio != 0) return byPrio;
            return a.createdAt.compareTo(b.createdAt);
          });

        if (pendings.isEmpty) break;

        final batch = pendings.take(maxParallel).toList();
        await Future.wait(batch.map(_processOne));
        await _save();
      }

      // Programar wake basado en el próximo nextAttemptAt
      final now = DateTime.now().millisecondsSinceEpoch;
      final upcoming = _tasks
          .where((t) =>
      (t.state == UploadState.pending || t.state == UploadState.failed) &&
          t.nextAttemptAt != null &&
          t.nextAttemptAt! > now)
          .map((t) => t.nextAttemptAt!)
          .fold<int?>(null, (minTs, ts) => minTs == null ? ts : math.min(minTs, ts));

      if (upcoming != null) {
        final delayMs = math.max(250, upcoming - now);
        _armWake(Duration(milliseconds: delayMs));
      } else {
        _wake?.cancel();
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _processOne(UploadTask t) async {
    final idx = _tasks.indexWhere((e) => e.id == t.id);
    if (idx < 0) return;

    _tasks[idx] = t.copy(state: UploadState.uploading, lastError: null);
    await _save();
    hook?.call('start', _tasks[idx]);

    try {
      final f = File(t.localPath);
      if (!await f.exists()) throw Exception('Archivo no encontrado');

      final res = await uploader.upload(file: f, sha256hex: t.sha256hex);

      if (!res.ok) {
        final int status = (res.status is int) ? res.status : 0;
        throw _HttpLikeException(
          status: status,
          message: res.error ?? 'HTTP $status',
        );
      }

      _tasks[idx] = _tasks[idx].copy(state: UploadState.verifying);
      await _save();

      final serverHash = res.serverHash;
      if (serverHash != null && serverHash != t.sha256hex) {
        throw StateError('Checksum mismatch');
      }

      // mover a media/
      final name = p.basename(t.localPath);
      final dst = await MediaPaths.mediaFile(name);
      await File(t.localPath).rename(dst.path);

      _tasks[idx] = _tasks[idx].copy(
        state: UploadState.done,
        remoteUrl: res.url ?? dst.uri.toString(),
        lastError: null,
      );
      hook?.call('success', _tasks[idx], data: {'url': res.url});
    } catch (e) {
      bool terminal = false;
      int? httpStatus;

      if (e is _HttpLikeException) {
        httpStatus = e.status;
        terminal = httpStatus >= 400 &&
            httpStatus < 500 &&
            httpStatus != 408 &&
            httpStatus != 429;
      }

      final nextDelayMs =
      terminal ? null : _backoffDecorrelated(baseMs: 1000, maxMs: 21600 * 1000);

      _tasks[idx] = _tasks[idx].copy(
        state: UploadState.failed,
        retries: terminal ? _tasks[idx].retries : _tasks[idx].retries + 1,
        lastError: e.toString(),
        nextAttemptAt: nextDelayMs == null
            ? null
            : DateTime.now().millisecondsSinceEpoch + nextDelayMs,
      );

      // persistimos también el nuevo prevSleepMs
      await _save();

      hook?.call('error', _tasks[idx],
          data: {'status': httpStatus, 'err': e.toString()});
    }
  }

  // ---------- Backoff: Decorrelated Jitter (estado) ----------
  // sleep = random(base, min(max, previous*3))
  int _backoffDecorrelated({required int baseMs, required int maxMs}) {
    final minMs = baseMs;
    final maxNext = math.min(maxMs, _prevSleepMs * 3);
    final span = math.max(1, maxNext - minMs);
    final ms = minMs + math.Random().nextInt(span);
    _prevSleepMs = ms.clamp(500, maxMs);
    return ms;
  }

  // ---------- utilidades de imagen ----------
  Future<void> _normalizeImageIfNeeded(File f) async {
    try {
      final ext = p.extension(f.path).toLowerCase();
      if (ext != '.jpg' && ext != '.jpeg') return;

      final bytes = await f.readAsBytes();
      final img = imglib.decodeImage(bytes);
      if (img == null) return;
      final fixed = imglib.bakeOrientation(img);
      final out = imglib.encodeJpg(fixed, quality: 90);
      await f.writeAsBytes(out, flush: true);
    } catch (_) {}
  }

  Future<void> _genThumb(File src, File dst, {int maxSide = 300}) async {
    try {
      final bytes = await src.readAsBytes();
      final img = imglib.decodeImage(bytes);
      if (img == null) return;
      final resized = imglib.copyResize(
        img,
        width: img.width >= img.height ? maxSide : null,
        height: img.width < img.height ? maxSide : null,
      );
      await dst.writeAsBytes(imglib.encodeJpg(resized, quality: 80), flush: true);
    } catch (_) {}
  }
}

// Excepción auxiliar para representar errores “tipo HTTP”
class _HttpLikeException implements Exception {
  final int status;
  final String message;
  _HttpLikeException({required this.status, required this.message});
  @override
  String toString() => 'HttpError($status): $message';
}
