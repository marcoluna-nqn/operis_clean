// lib/utils/perf.dart
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';

/// Cronómetro simple + traza en DevTools
class Perf {
  static Future<T> run<T>(String name, Future<T> Function() op) async {
    final sw = Stopwatch()..start();
    final task = dev.TimelineTask()..start(name);
    try {
      return await op();
    } finally {
      sw.stop();
      task.finish();
      dev.log('⏱️ $name: ${sw.elapsedMilliseconds} ms');
    }
  }
}

/// JSON pesado en isolate
class Background {
  static Future<T> jsonDecodeTyped<T>(String raw) async =>
      compute<String, T>((r) => jsonDecode(r) as T, raw);

  static Future<String> jsonEncodeTyped(Object value) async =>
      compute<Object, String>(jsonEncode, value);
}

/// Debouncer simple
class Debouncer {
  Debouncer({this.ms = 250});
  final int ms;
  Timer? _t;

  void call(VoidCallback f) {
    _t?.cancel();
    _t = Timer(Duration(milliseconds: ms), f);
  }

  Future<void> run(Future<void> Function() f) async {
    _t?.cancel();
    final c = Completer<void>();
    _t = Timer(Duration(milliseconds: ms), () async {
      try { await f(); c.complete(); } catch (e, s) { c.completeError(e, s); }
    });
    return c.future;
  }

  void dispose() => _t?.cancel();
}
