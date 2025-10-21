import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SheetMeta {
  final String id;
  String name;
  final int columns;
  final int initialRows;

  SheetMeta({
    required this.id,
    required this.name,
    required this.columns,
    required this.initialRows,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'columns': columns,
    'initialRows': initialRows,
  };

  factory SheetMeta.fromJson(Map<String, dynamic> j) => SheetMeta(
    id: (j['id'] ?? '') as String,
    name: (j['name'] as String?) ?? 'Bitácora',
    columns: (j['columns'] as int?) ?? 5,
    initialRows: (j['initialRows'] as int?) ?? 60,
  );
}

class SheetRepo {
  static const _kKey = 'sheets';

  static Future<List<SheetMeta>> all() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_kKey) ?? <String>[];
    return raw
        .map((e) => SheetMeta.fromJson(json.decode(e) as Map<String, dynamic>))
        .toList();
  }

  static Future<void> upsert(SheetMeta m) async {
    final sp = await SharedPreferences.getInstance();
    final list = await all();
    final i = list.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      list[i] = m;
    } else {
      list.add(m);
    }
    await sp.setStringList(
      _kKey,
      list.map((e) => json.encode(e.toJson())).toList(),
    );
  }

  static Future<void> rename(String id, String newName) async {
    final list = await all();
    final i = list.indexWhere((x) => x.id == id);
    if (i >= 0) {
      list[i].name = newName;
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(
        _kKey,
        list.map((e) => json.encode(e.toJson())).toList(),
      );
    }
  }
}
