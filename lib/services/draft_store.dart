// lib/services/draft_store.dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DraftStore {
  const DraftStore();

  Future<File> _fileFor(String sheetId) async {
    final dir = await getApplicationSupportDirectory();
    final name = 'bitacora_draft_${sheetId.isEmpty ? "local" : sheetId}.json';
    return File(p.join(dir.path, name));
  }

  Future<SheetDraft?> load(String sheetId) async {
    try {
      final f = await _fileFor(sheetId);
      if (!await f.exists()) return null;
      final txt = await f.readAsString();
      final map = jsonDecode(txt) as Map<String, dynamic>;
      return SheetDraft.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String sheetId, SheetDraft draft) async {
    final f = await _fileFor(sheetId);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(draft.toJson()), flush: true);
    // write-swap para evitar corrupción si la app se cierra en medio
    if (await f.exists()) await f.delete();
    await tmp.rename(f.path);
  }

  Future<void> clear(String sheetId) async {
    try {
      final f = await _fileFor(sheetId);
      if (await f.exists()) await f.delete();
    } catch (_) {/* no-op */}
  }
}

/// Modelo serializable del borrador
class SheetDraft {
  final List<String> headers;
  final List<RowDraft> rows;

  SheetDraft({required this.headers, required this.rows});

  Map<String, dynamic> toJson() => {
        'headers': headers,
        'rows': rows.map((e) => e.toJson()).toList(),
      };

  factory SheetDraft.fromJson(Map<String, dynamic> json) => SheetDraft(
        headers: (json['headers'] as List).map((e) => e as String).toList(),
        rows: (json['rows'] as List)
            .map((e) => RowDraft.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class RowDraft {
  final List<String> cells;
  final List<String> photos;
  final double? lat;
  final double? lng;

  RowDraft({
    required this.cells,
    required this.photos,
    this.lat,
    this.lng,
  });

  Map<String, dynamic> toJson() => {
        'cells': cells,
        'photos': photos,
        'lat': lat,
        'lng': lng,
      };

  factory RowDraft.fromJson(Map<String, dynamic> json) => RowDraft(
        cells: (json['cells'] as List).map((e) => e as String).toList(),
        photos: (json['photos'] as List).map((e) => e as String).toList(),
        lat: (json['lat'] == null) ? null : (json['lat'] as num).toDouble(),
        lng: (json['lng'] == null) ? null : (json['lng'] as num).toDouble(),
      );
}
