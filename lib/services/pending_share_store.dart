// lib/services/pending_share_store.dart
import 'dart:async' show StreamSubscription;
import 'dart:convert';
import 'dart:io';

import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'net.dart';

/// Archivo a compartir encolado.
class PendingShareFile {
  final String path;
  final String name;
  final String? mimeType;

  const PendingShareFile({
    required this.path,
    required this.name,
    this.mimeType,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'mimeType': mimeType,
  };

  factory PendingShareFile.fromJson(Map<String, dynamic> j) => PendingShareFile(
    path: j['path'] as String,
    name: j['name'] as String,
    mimeType: j['mimeType'] as String?,
  );
}

/// Ítem de la cola (soporta prioridad/TTL/reintentos).
class PendingShare {
  final List<PendingShareFile> files;
  final String subject;
  final String text;
  final DateTime createdAt;

  /// 0..100 (100 = mayor prioridad)
  final int priority;

  /// Reintentos realizados
  final int attempts;

  /// Vencimiento opcional (descartar si expira)
  final DateTime? expiresAt;

  const PendingShare({
    required this.files,
    required this.subject,
    required this.text,
    required this.createdAt,
    this.priority = 50,
    this.attempts = 0,
    this.expiresAt,
  });

  PendingShare copyWith({
    List<PendingShareFile>? files,
    String? subject,
    String? text,
    DateTime? createdAt,
    int? priority,
    int? attempts,
    DateTime? expiresAt,
  }) {
    return PendingShare(
      files: files ?? this.files,
      subject: subject ?? this.subject,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      priority: priority ?? this.priority,
      attempts: attempts ?? this.attempts,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'files': files.map((e) => e.toJson()).toList(),
    'subject': subject,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'priority': priority,
    'attempts': attempts,
    'expiresAt': expiresAt?.toIso8601String(),
  };

  factory PendingShare.fromJson(Map<String, dynamic> j) => PendingShare(
    files: (j['files'] as List<dynamic>? ?? const <dynamic>[])
        .map((e) => PendingShareFile.fromJson(
      Map<String, dynamic>.from(e as Map<String, dynamic>),
    ))
        .toList(),
    subject: (j['subject'] ?? '') as String,
    text: (j['text'] ?? '') as String,
    createdAt:
    DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    priority: (j['priority'] as num?)?.toInt() ?? 50,
    attempts: (j['attempts'] as num?)?.toInt() ?? 0,
    expiresAt: (j['expiresAt'] as String?) != null
        ? DateTime.tryParse(j['expiresAt'] as String)
        : null,
  );
}

/// Abstracción del cliente de red (DI).
abstract class NetClient {
  Future<bool> isOnline();
  Stream<bool> get onOnline;
}

/// Implementación por defecto que usa tu Net.I.
class DefaultNetClient implements NetClient {
  const DefaultNetClient();
  @override
  Future<bool> isOnline() => Net.I.isOnline();
  @override
  Stream<bool> get onOnline => Net.I.onOnline;
}

/// Abstracción del cliente de share (DI).
abstract class ShareClient {
  Future<ShareResult> share(ShareParams params);
}

/// Implementación por defecto que usa SharePlus.
class SharePlusClient implements ShareClient {
  const SharePlusClient();
  @override
  Future<ShareResult> share(ShareParams params) =>
      SharePlus.instance.share(params);
}

/// Abstracción de reloj (DI).
abstract class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now();
}

/// Cola de “share” resiliente con prioridad/TTL/backoff con jitter.
/// Persiste en SharedPreferences.
class PendingShareStore {
  PendingShareStore._({
    NetClient? net,
    ShareClient? share,
    Clock? clock,
    Set<String>? allowedMimePrefixes,
    // Defaults seguros
    this.maxQueue = 40,
    this.minBackoffSec = 15,
    this.maxBackoffSec = 900,
    this.maxFileSizeMB = 50,
  })  : _net = net ?? const DefaultNetClient(),
        _share = share ?? const SharePlusClient(),
        _clock = clock ?? const SystemClock(),
        _allowedMimePrefixes = allowedMimePrefixes ??
            const {
              'image/', // fotos
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', // xlsx
              'text/csv',
              'application/pdf',
            };

  static final PendingShareStore instance = PendingShareStore._();
  static PendingShareStore get I => instance;

  // ------ Config ------
  final int maxQueue;
  final int minBackoffSec;
  final int maxBackoffSec;
  final int maxFileSizeMB;
  final Set<String> _allowedMimePrefixes;

  // ------ DI ------
  final NetClient _net;
  final ShareClient _share;
  final Clock _clock;

  // ------ Storage keys (v2) ------
  static const String _kQueue = 'pending_share_queue_v2';
  static const String _kNextTs = 'pending_share_next_attempt_ts_v2';

  // ------ Estado ------
  StreamSubscription<bool>? _onlineSub;
  bool _processing = false;

  // ------ Telemetría (opcional) ------
  void Function(PendingShare item)? onAttempt;
  void Function(PendingShare item, ShareResultStatus status)? onSuccess;
  void Function(PendingShare item, Object error, StackTrace st)? onFail;

  // ===== API =====

  Future<void> init() async {
    await _onlineSub?.cancel();
    _onlineSub = _net.onOnline.listen((_) => processQueueIfOnline());
    await processQueueIfOnline();
  }

  Future<void> dispose() async {
    await _onlineSub?.cancel();
    _onlineSub = null;
  }

  /// Encola archivos para compartir.
  /// - [priority] 0..100
  /// - [ttl] si se define, descarta el ítem al vencer
  /// - [collapseWithSame] si true, combina con el último de mismo subject/text
  Future<void> enqueueFiles(
      List<XFile> files, {
        required String subject,
        String? text,
        int priority = 50,
        Duration? ttl,
        bool collapseWithSame = false,
      }) async {
    final now = _clock.now();
    final boundedPriority = priority < 0
        ? 0
        : (priority > 100 ? 100 : priority);

    final item = PendingShare(
      files: files
          .map((f) => PendingShareFile(
        path: f.path,
        name: f.name,
        mimeType: f.mimeType,
      ))
          .toList(),
      subject: subject,
      text: text ?? '',
      createdAt: now,
      priority: boundedPriority,
      expiresAt: ttl == null ? null : now.add(ttl),
    );

    final List<PendingShare> all = await _load();

    // De-dupe por fingerprint simple.
    final String fp =
        '${item.subject}|${item.text}|${item.files.map((f) => f.path).join(',')}';
    final bool already = all.any((it) =>
    '${it.subject}|${it.text}|${it.files.map((f) => f.path).join(',')}' ==
        fp);

    if (!already) {
      if (collapseWithSame) {
        final int idx = all.lastIndexWhere(
                (it) => it.subject == item.subject && it.text == item.text);
        if (idx != -1) {
          final existing = all[idx];
          final Set<String> have = existing.files.map((f) => f.path).toSet();
          final List<PendingShareFile> merged = <PendingShareFile>[
            ...existing.files,
            ...item.files.where((f) => !have.contains(f.path)),
          ];
          all[idx] = existing.copyWith(files: merged);
        } else {
          all.add(item);
        }
      } else {
        all.add(item);
      }

      if (all.length > maxQueue) {
        all.removeRange(0, all.length - maxQueue);
      }
      await _save(all);
    }
  }

  Future<void> clear() async => _save(const <PendingShare>[]);

  /// Procesa la cola si hay conectividad y respeta backoff/jitter.
  Future<void> processQueueIfOnline() async {
    if (_processing) return;
    if (!await _net.isOnline()) return;

    final DateTime? next = await _getNextAttemptAt();
    final DateTime now = _clock.now();
    if (next != null && now.isBefore(next)) return;

    _processing = true;
    try {
      final List<PendingShare> all = await _load();

      // Purga vencidos.
      all.removeWhere(
              (it) => it.expiresAt != null && now.isAfter(it.expiresAt!));

      if (all.isEmpty) {
        await _save(all);
        await _setNextAttemptAt(now);
        return;
      }

      // Orden: prioridad desc, luego más antiguo primero.
      all.sort((a, b) {
        final int p = b.priority.compareTo(a.priority);
        return p != 0 ? p : a.createdAt.compareTo(b.createdAt);
      });

      // Tomamos head y validamos archivos (existencia/tamaño/mime).
      PendingShare head = all.first;
      final List<PendingShareFile> validFiles = <PendingShareFile>[];

      for (final PendingShareFile f in head.files) {
        final File df = File(f.path);
        if (!df.existsSync()) continue;

        final int size = df.lengthSync();
        final int maxBytes = maxFileSizeMB * 1024 * 1024;
        if (size > maxBytes) continue;

        final String? mt = f.mimeType;
        if (mt == null ||
            !_allowedMimePrefixes.any((pref) => mt.startsWith(pref))) {
          // Si no hay mime válido, dejar pasar por extensión conocida.
          if (!_isProbablyShareableByExt(f.name)) continue;
        }
        validFiles.add(f);
      }

      if (validFiles.isEmpty) {
        // Nada útil que compartir -> eliminar y continuar.
        all.removeAt(0);
        await _save(all);
        await _setNextAttemptAt(now);
        if (all.isNotEmpty) {
          _processing = false;
          await processQueueIfOnline();
        }
        return;
      }

      // Intenta compartir.
      onAttempt?.call(head);
      final List<XFile> xfiles = validFiles
          .map((f) => XFile(
        f.path,
        name: f.name,
        mimeType: f.mimeType ?? 'application/octet-stream',
      ))
          .toList();

      final ShareResult res = await _share.share(
        ShareParams(files: xfiles, subject: head.subject, text: head.text),
      );

      if (res.status == ShareResultStatus.success) {
        onSuccess?.call(head, res.status);
        all.removeAt(0);
        await _save(all);
        await _setNextAttemptAt(now);
        if (all.isNotEmpty) {
          _processing = false;
          await processQueueIfOnline();
        }
        return;
      } else {
        // Dismissed/cancelled -> backoff por intentos con jitter.
        final int nextSec = _computeBackoffWithJitter(
          head.attempts + 1,
          minBackoffSec,
          maxBackoffSec,
        );
        head = head.copyWith(attempts: head.attempts + 1);
        all[0] = head;
        await _save(all);
        await _setNextAttemptAt(now.add(Duration(seconds: nextSec)));
        return;
      }
    } catch (e, st) {
      // Error: incrementa intentos y reprograma.
      try {
        final List<PendingShare> all = await _load();
        if (all.isNotEmpty) {
          final PendingShare head =
          all.first.copyWith(attempts: all.first.attempts + 1);
          all[0] = head;
          await _save(all);
          onFail?.call(head, e, st);
          final int nextSec = _computeBackoffWithJitter(
            head.attempts,
            minBackoffSec,
            maxBackoffSec,
          );
          await _setNextAttemptAt(_clock.now().add(Duration(seconds: nextSec)));
        }
      } catch (_) {
        // swallow
      }
    } finally {
      _processing = false;
    }
  }

  // ===== Persistencia (SharedPreferences) =====

  Future<List<PendingShare>> _load() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final List<String> raw = p.getStringList(_kQueue) ?? const <String>[];

    // Migración blanda desde v1 si existiera.
    final List<String> legacy =
        p.getStringList('pending_share_queue_v1') ?? const <String>[];

    final List<String> both = <String>[...raw, ...legacy];

    final List<PendingShare> out = <PendingShare>[];
    for (final String s in both) {
      try {
        final Map<String, dynamic> j =
        Map<String, dynamic>.from(jsonDecode(s) as Map<String, dynamic>);
        out.add(PendingShare.fromJson(j));
      } catch (_) {
        // Ignorar corruptos
      }
    }
    if (out.length > maxQueue) {
      out.removeRange(0, out.length - maxQueue);
    }
    return out;
  }

  Future<void> _save(List<PendingShare> items) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final List<String> lines =
    items.map((e) => jsonEncode(e.toJson())).toList();
    await p.setStringList(_kQueue, lines);
  }

  Future<DateTime?> _getNextAttemptAt() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final String? raw = p.getString(_kNextTs);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> _setNextAttemptAt(DateTime when) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setString(_kNextTs, when.toIso8601String());
  }

  // ===== Utilidades =====

  bool _isProbablyShareableByExt(String name) {
    final String n = name.toLowerCase();
    return n.endsWith('.xlsx') ||
        n.endsWith('.csv') ||
        n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.png') ||
        n.endsWith('.pdf');
  }

  /// Backoff exponencial con jitter (+/- 20%), acotado a [min,max].
  int _computeBackoffWithJitter(int attempts, int minSec, int maxSec) {
    final int factor = attempts <= 0 ? 1 : (1 << (attempts - 1));
    final int unclamped = minSec * factor;
    final int base = unclamped < minSec
        ? minSec
        : (unclamped > maxSec ? maxSec : unclamped);
    const double jitter = 0.2; // 20%
    final double low = base * (1 - jitter);
    final double high = base * (1 + jitter);
    final int range = (high - low).abs().ceil() + 1;
    final int offset = _clock.now().microsecondsSinceEpoch % range;
    final int res = low.floor() + offset;
    final int clamped = res < minSec ? minSec : (res > maxSec ? maxSec : res);
    return clamped;
  }
}
