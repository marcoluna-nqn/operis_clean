import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class AuditEvent {
  final DateTime ts;
  final String action;
  final String field;
  final String key;
  final String oldValue;
  final String newValue;

  AuditEvent({
    required this.ts,
    required this.action,
    required this.field,
    required this.key,
    this.oldValue = '',
    this.newValue = '',
  });

  factory AuditEvent.fromJson(Map<String, dynamic> j) => AuditEvent(
    ts: DateTime.parse(j['ts'] as String),
    action: (j['action'] ?? '') as String,
    field: (j['field'] ?? '') as String,
    key: (j['key'] ?? '') as String,
    oldValue: (j['oldValue'] ?? '') as String,
    newValue: (j['newValue'] ?? '') as String,
  );

  Map<String, dynamic> toJson() => {
    'ts': ts.toIso8601String(),
    'action': action,
    'field': field,
    'key': key,
    'oldValue': oldValue,
    'newValue': newValue,
  };
}

class AuditService {
  static const _fileName = 'audit.log';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<void> log({
    required String action,
    required String field,
    required String key,
    String oldValue = '',
    String newValue = '',
    DateTime? ts,
  }) async {
    final f = await _file();
    final line = jsonEncode(
      AuditEvent(
        ts: ts ?? DateTime.now().toUtc(),
        action: action,
        field: field,
        key: key,
        oldValue: oldValue,
        newValue: newValue,
      ).toJson(),
    );
    await f.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }

  static Future<List<AuditEvent>> readAll() async {
    final f = await _file();
    if (!await f.exists()) return [];
    final lines = await f.readAsLines();
    final out = <AuditEvent>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        out.add(AuditEvent.fromJson(jsonDecode(line) as Map<String, dynamic>));
      } catch (_) {}
    }
    return out;
  }

  static Future<void> clear() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }
}
