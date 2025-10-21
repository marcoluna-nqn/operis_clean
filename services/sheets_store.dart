// lib/services/sheets_store.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sheet_meta.dart';

class SheetsStore extends ChangeNotifier {
  static const _kKey = 'gridnote_sheets_meta';
  final List<SheetMeta> _all = [];

  List<SheetMeta> get all => List.unmodifiable(_all);

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_kKey);
    _all.clear();

    if (s != null && s.isNotEmpty) {
      _all.addAll(_decodeList(s));
    } else {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      _all.addAll([
        SheetMeta(
          id: nowMs,
          name: 'Planilla 1',
          createdAt: nowMs,
        ),
        SheetMeta(
          id: nowMs + 109,
          name: 'rrr',
          createdAt: nowMs,
        ),
      ]);
      await _persist();
    }

    notifyListeners();
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kKey, _encodeList(_all));
  }

  /// Devuelve una meta por id (admite string o int en la comparación).
  SheetMeta byId(String id) {
    final found = _all.where((e) => e.id.toString() == id);
    if (found.isNotEmpty) return found.first;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return SheetMeta(id: int.tryParse(id) ?? nowMs, name: 'Planilla', createdAt: nowMs);
  }

  Future<void> rename(String id, String name) async {
    final i = _all.indexWhere((e) => e.id.toString() == id);
    if (i == -1) return;
    // copyWith solo con los campos que tu modelo define
    _all[i] = _all[i].copyWith(name: name);
    await _persist();
    notifyListeners();
  }

  Future<int> addNew([String name = 'Nueva planilla']) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final meta = SheetMeta(id: nowMs, name: name, createdAt: nowMs);
    _all.insert(0, meta);
    await _persist();
    notifyListeners();
    return nowMs;
  }

  // ---------- JSON helpers ----------
  String _encodeList(List<SheetMeta> list) =>
      jsonEncode(list.map(_toJson).toList());

  List<SheetMeta> _decodeList(String s) {
    final raw = jsonDecode(s);
    if (raw is! List) return <SheetMeta>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(_fromJson)
        .toList(growable: false);
  }

  Map<String, dynamic> _toJson(SheetMeta m) => {
    'id': m.id,                 // int
    'name': m.name,             // String
    'createdAt': m.createdAt,   // int (epoch-ms)
  };

  SheetMeta _fromJson(Map<String, dynamic> j) {
    final id = (j['id'] is int)
        ? j['id'] as int
        : int.tryParse('${j['id']}') ?? DateTime.now().millisecondsSinceEpoch;

    final createdAt = (j['createdAt'] is int)
        ? j['createdAt'] as int
        : int.tryParse('${j['createdAt']}') ??
        DateTime.now().millisecondsSinceEpoch;

    return SheetMeta(
      id: id,
      name: '${j['name'] ?? 'Planilla'}',
      createdAt: createdAt,
    );
  }
}
