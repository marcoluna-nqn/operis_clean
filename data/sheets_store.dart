// Persistencia súper simple en JSON local (sin Drift).
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SheetsStore {
  SheetsStore();

  Future<Directory> _dir() async {
    final root = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(root.path, 'sheets'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _file(String id) async =>
      File(p.join((await _dir()).path, '$id.json'));

  // ---------- API pública ----------
  Future<List<SheetSummary>> list() async {
    final d = await _dir();
    final out = <SheetSummary>[];
    for (final f in d
        .listSync()
        .whereType<File>()
        .where((e) => e.path.endsWith('.json'))) {
      try {
        final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        out.add(SheetSummary.fromJson(m));
      } catch (_) {}
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<String> create({required String title, int columns = 5}) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final pay = SheetPayload(
      id: id,
      title: title,
      headers: List.filled(columns, ''),
      rows: List.generate(60, (_) => List.filled(columns, '')),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      sheetPhotos: const [],
      sheetLat: null,
      sheetLng: null,
    );
    await save(pay);
    return id;
  }

  Future<SheetPayload?> load(String id) async {
    final f = await _file(id);
    if (!await f.exists()) return null;
    final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return SheetPayload.fromJson(m);
  }

  Future<void> save(SheetPayload p) async {
    final f = await _file(p.id);
    final json = jsonEncode(p.copyWith(updatedAt: DateTime.now()).toJson());
    await f.writeAsString(json, flush: true);
  }

  Future<void> delete(String id) async {
    final f = await _file(id);
    if (await f.exists()) await f.delete();
  }

  // Sugerencias de títulos (frecuentes recientes)
  Future<List<String>> titleSuggestions({int max = 6}) async {
    final items = await list();
    final freq = <String, int>{};
    for (final s in items) {
      if (s.title.trim().isEmpty) continue;
      freq[s.title] = (freq[s.title] ?? 0) + 1;
    }
    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(max).map((e) => e.key).toList();
  }
}

// ---------- Modelos ----------
class SheetSummary {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double? sheetLat;
  final double? sheetLng;
  final int rowsCount;

  SheetSummary({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.rowsCount,
    this.sheetLat,
    this.sheetLng,
  });

  factory SheetSummary.fromJson(Map<String, dynamic> m) => SheetSummary(
        id: m['id'] as String,
        title: (m['title'] as String?) ?? '',
        createdAt: DateTime.parse(m['createdAt'] as String),
        updatedAt: DateTime.parse(m['updatedAt'] as String),
        rowsCount: (m['rows'] as List).length,
        sheetLat: (m['sheetLat'] as num?)?.toDouble(),
        sheetLng: (m['sheetLng'] as num?)?.toDouble(),
      );
}

class SheetPayload {
  final String id;
  final String title;
  final List<String> headers;
  final List<List<String>> rows;
  final List<String> sheetPhotos;
  final double? sheetLat;
  final double? sheetLng;
  final DateTime createdAt;
  final DateTime updatedAt;

  SheetPayload({
    required this.id,
    required this.title,
    required this.headers,
    required this.rows,
    required this.sheetPhotos,
    required this.sheetLat,
    required this.sheetLng,
    required this.createdAt,
    required this.updatedAt,
  });

  SheetPayload copyWith({
    String? title,
    List<String>? headers,
    List<List<String>>? rows,
    List<String>? sheetPhotos,
    double? sheetLat,
    double? sheetLng,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      SheetPayload(
        id: id,
        title: title ?? this.title,
        headers: headers ?? this.headers,
        rows: rows ?? this.rows,
        sheetPhotos: sheetPhotos ?? this.sheetPhotos,
        sheetLat: sheetLat ?? this.sheetLat,
        sheetLng: sheetLng ?? this.sheetLng,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'headers': headers,
        'rows': rows,
        'sheetPhotos': sheetPhotos,
        'sheetLat': sheetLat,
        'sheetLng': sheetLng,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory SheetPayload.fromJson(Map<String, dynamic> m) => SheetPayload(
        id: m['id'] as String,
        title: (m['title'] as String?) ?? '',
        headers: (m['headers'] as List).map((e) => e as String).toList(),
        rows: (m['rows'] as List)
            .map((r) => (r as List).map((e) => e as String).toList())
            .toList(),
        sheetPhotos: ((m['sheetPhotos'] as List?) ?? const [])
            .map((e) => e as String)
            .toList(),
        sheetLat: (m['sheetLat'] as num?)?.toDouble(),
        sheetLng: (m['sheetLng'] as num?)?.toDouble(),
        createdAt: DateTime.parse(m['createdAt'] as String),
        updatedAt: DateTime.parse(m['updatedAt'] as String),
      );
}
