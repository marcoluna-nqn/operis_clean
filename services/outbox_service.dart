// lib/services/outbox_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../db/app_db.dart';
import 'connectivity_service.dart';

typedef OutboxHandler = Future<bool> Function(Map<String, dynamic> payload);

class OutboxService {
  OutboxService._();
  static final OutboxService I = OutboxService._();

  final Map<String, OutboxHandler> _handlers = {};
  Timer? _loop;
  bool _running = false;

  void register(String kind, OutboxHandler handler) {
    _handlers[kind] = handler;
  }

  Future<void> enqueue(String kind, Map<String, dynamic> payload, {DateTime? at}) async {
    final db = await AppDb.instance();
    await db.enqueueJob(
      id: const Uuid().v4(),
      kind: kind,
      payload: payload,
      scheduleAt: at,
    );
    _poke();
  }

  void start() {
    _loop?.cancel();
    _loop = Timer.periodic(const Duration(seconds: 20), (_) => _tick());
    _poke();
  }

  void stop() {
    _loop?.cancel();
    _loop = null;
  }

  Future<void> _poke() async => _tick();

  Future<void> _tick() async {
    if (_running) return;
    _running = true;
    try {
      final online = await ConnectivityService.I.isOnline();
      if (!online) return;

      final db = await AppDb.instance();
      final now = DateTime.now();
      final jobs = await db.dueJobs(now);

      for (final j in jobs) {
        final handler = _handlers[j.kind];
        if (handler == null) {
          await db.markJobFailed(j.id);
          continue;
        }

        final payload = jsonDecode(j.payloadJson) as Map<String, dynamic>;
        try {
          final ok = await handler(payload);
          if (ok) {
            await db.markJobDone(j.id);
          } else {
            final backoff = _calcBackoff(j.attempts);
            await db.rescheduleJob(j.id, j.attempts, backoff);
          }
        } catch (_) {
          final backoff = _calcBackoff(j.attempts);
          await db.rescheduleJob(j.id, j.attempts, backoff);
        }
      }
    } finally {
      _running = false;
    }
  }

  Duration _calcBackoff(int attempts) {
    // exponencial con jitter
    final base = Duration(seconds: 5 * (1 << attempts).clamp(1, 60)); // hasta ~5*2^6=320s
    final jitterMs = Random().nextInt(1500);
    return base + Duration(milliseconds: jitterMs);
    // si querés un máximo: .clamp(Duration(seconds:5), Duration(minutes:15))
  }
}
