// lib/models/sheet_data.dart
import 'dart:convert';


class RowData {
  final List<String> cells;
  final List<String> photos;
  final double? lat;
  final double? lng;


  RowData({
    required this.cells,
    List<String>? photos,
    this.lat,
    this.lng,
  }) : photos = photos ?? <String>[];


  RowData copyWith({
    List<String>? cells,
    List<String>? photos,
    double? lat,
    double? lng,
  }) => RowData(
    cells: cells ?? List<String>.from(this.cells),
    photos: photos ?? List<String>.from(this.photos),
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
  );


  Map<String, dynamic> toJson() => {
    'cells': cells,
    'photos': photos,
    'lat': lat,
    'lng': lng,
  };


  factory RowData.fromJson(Map<String, dynamic> j) => RowData(
    cells: (j['cells'] as List).map((e) => (e ?? '').toString()).toList(),
    photos: (j['photos'] as List? ?? const <dynamic>[])
        .map((e) => (e ?? '').toString())
        .toList(),
    lat: (j['lat'] is num) ? (j['lat'] as num).toDouble() : null,
    lng: (j['lng'] is num) ? (j['lng'] as num).toDouble() : null,
  );
}


class SheetData {
  static const int schemaVersion = 2;


  final String sheetId;
  final String title;
  final List<String> headers;
  final List<RowData> rows;
  final DateTime updatedAt;


  SheetData({
    required this.sheetId,
    required this.title,
    required this.headers,
    required this.rows,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc();


  Map<String, dynamic> toJson() => {
    'v': schemaVersion,
    'sheetId': sheetId,
    'title': title,
    'headers': headers,
    'rows': rows.map((r) => r.toJson()).toList(),
    'updatedAt': updatedAt.toIso8601String(),
  };


  factory SheetData.fromJson(Map<String, dynamic> j) => SheetData(
    sheetId: j['sheetId'] as String,
    title: j['title'] as String? ?? 'Bitácora',
    headers: (j['headers'] as List).map((e) => (e ?? '').toString()).toList(),
    rows: (j['rows'] as List)
        .map((e) => RowData.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
    updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '')?.toUtc(),
  );


  String toPrettyJson() => const JsonEncoder.withIndent(' ').convert(toJson());
}