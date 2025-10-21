import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Telemetría local “append-only” con LJSON (una línea por evento).
class TelemetryService {
  TelemetryService._();
  static final TelemetryService I = TelemetryService._();

  IOSink? _sink;

  Future<void> init() async {
    if (_sink != null) return;
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/telemetry.log');
    _sink = f.openWrite(mode: FileMode.append, encoding: utf8);
  }

  Future<void> event(String name, {Map<String, Object?> extra = const {}}) async {
    await init();
    final payload = {
      't': DateTime.now().toIso8601String(),
      'evt': name,
      'extra': extra,
    };
    _sink?.writeln(jsonEncode(payload));
  }

  Future<void> dispose() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }
}
