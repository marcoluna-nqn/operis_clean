// lib/services/queued_share_service.dart
// ignore_for_file: cancel_subscriptions
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart' as cp;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class QueuedShareService {
  QueuedShareService._();
  static final I = QueuedShareService._();

  bool _started = false;
  StreamSubscription<dynamic>? _sub; // v6 emite List<ConnectivityResult>, v5 emite uno solo
  bool _flushing = false;

  void ensureStarted() {
    if (_started) return;
    _started = true;

    _sub = cp.Connectivity().onConnectivityChanged.listen((event) async {
      final bool hasWifi = (event is List<cp.ConnectivityResult>)
          ? event.contains(cp.ConnectivityResult.wifi)
          : (event == cp.ConnectivityResult.wifi);
      if (hasWifi) await _flush();
    });

    unawaited(_flush());
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }

  Future<bool> shareOrEnqueue({
    required String filePath,
    String subject = '',
    String text = '',
  }) async {
    final chk = await cp.Connectivity().checkConnectivity();
    final hasWifi = (chk is List<cp.ConnectivityResult>)
        ? chk.contains(cp.ConnectivityResult.wifi)
        : (chk == cp.ConnectivityResult.wifi);

    if (hasWifi) {
      try {
        await SharePlus.instance.share(
          ShareParams(subject: subject, text: text, files: [XFile(filePath)]),
        );
        return true;
      } catch (_) {/* si falla, encola */}
    }
    await _enqueue(_Item(filePath: filePath, subject: subject, text: text));
    return false;
  }

  Future<File> _queueFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File(p.join(dir.path, 'queued_shares.json'));
    if (!await f.exists()) {
      await f.writeAsString(jsonEncode(<Map<String, dynamic>>[]));
    }
    return f;
  }

  Future<void> _enqueue(_Item item) async {
    final f = await _queueFile();
    final list = List<Map<String, dynamic>>.from(
      (jsonDecode(await f.readAsString()) as List),
    );
    if (!list.any((e) => e['filePath'] == item.filePath)) {
      list.add(item.toJson());
      await f.writeAsString(jsonEncode(list), flush: true);
    }
  }

  Future<void> _flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      final f = await _queueFile();
      final list = List<Map<String, dynamic>>.from(
        (jsonDecode(await f.readAsString()) as List),
      );
      if (list.isEmpty) return;

      final items = list.map(_Item.fromJson).toList();
      for (final it in items) {
        if (!await File(it.filePath).exists()) {
          list.removeWhere((e) => e['filePath'] == it.filePath);
          continue;
        }
        try {
          await SharePlus.instance.share(
            ShareParams(
              subject: it.subject,
              text: it.text,
              files: [XFile(it.filePath)],
            ),
          );
          list.removeWhere((e) => e['filePath'] == it.filePath);
        } catch (_) {
          break; // sigue en cola
        }
      }
      await f.writeAsString(jsonEncode(list), flush: true);
    } finally {
      _flushing = false;
    }
  }
}

class _Item {
  final String filePath;
  final String subject;
  final String text;

  _Item({required this.filePath, required this.subject, required this.text});

  Map<String, dynamic> toJson() =>
      {'filePath': filePath, 'subject': subject, 'text': text};

  factory _Item.fromJson(Map<String, dynamic> j) => _Item(
    filePath: (j['filePath'] ?? '').toString(),
    subject: (j['subject'] ?? '').toString(),
    text: (j['text'] ?? '').toString(),
  );
}
