// lib/services/onboarding_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class OnboardingService {
  OnboardingService._();
  static final OnboardingService I = OnboardingService._();

  Future<bool> shouldShow(String key) async {
    final map = await _load();
    return (map['done'] as List?)?.contains(key) != true;
  }

  Future<void> markDone(String key) async {
    final map = await _load();
    final list = (map['done'] as List?)?.cast<String>().toList() ?? <String>[];
    if (!list.contains(key)) list.add(key);
    map['done'] = list;
    await _save(map);
  }

  Future<Map<String, dynamic>> _load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return <String, dynamic>{'done': <String>[]};
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{'done': <String>[]};
    }
  }

  Future<void> _save(Map<String, dynamic> j) async {
    final f = await _file();
    await f.writeAsString(jsonEncode(j), flush: true);
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/onboarding.json');
  }
}
