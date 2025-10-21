// Drift DB: hojas + filas (JSON), simple y sólido.
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_db.g.dart';

class Sheets extends Table {
  TextColumn get id => text()(); // p.ej. 'default'
  TextColumn get name => text().withDefault(const Constant('Bitácora'))();
  IntColumn get columns => integer().withDefault(const Constant(5))();
  TextColumn get headersJson =>
      text().withDefault(const Constant('[]'))(); // List<String>
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

class Rows extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sheetId => text().references(Sheets, #id)();
  IntColumn get index => integer()(); // posición visual
  TextColumn get cellsJson => text()(); // List<String>
  TextColumn get photosJson =>
      text().withDefault(const Constant('[]'))(); // List<String>
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();
  TextColumn get placeName => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  List<String> get customConstraints =>
      ['UNIQUE(sheet_id, "index") ON CONFLICT REPLACE'];
}

@DriftDatabase(tables: [Sheets, Rows])
class AppDb extends _$AppDb {
  AppDb() : super(_openConn());
  @override
  int get schemaVersion => 1;

  // Sheets
  Future<void> upsertSheet({
    required String id,
    String? name,
    int? columns,
    List<String>? headers,
  }) async {
    final now = DateTime.now();
    final s = SheetsCompanion(
      id: Value(id),
      name: name != null ? Value(name) : const Value.absent(),
      columns: columns != null ? Value(columns) : const Value.absent(),
      headersJson:
          headers != null ? Value(jsonEncode(headers)) : const Value.absent(),
      updatedAt: Value(now),
    );
    await into(sheets).insertOnConflictUpdate(s);
  }

  Future<SheetData?> fetchSheet(String id) async {
    final s =
        await (select(sheets)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (s == null) return null;
    final rs = await (select(rows)
          ..where((r) => r.sheetId.equals(id))
          ..orderBy([(r) => OrderingTerm.asc(r.index)]))
        .get();
    return SheetData(
      id: s.id,
      name: s.name,
      columns: s.columns,
      headers: (jsonDecode(s.headersJson) as List).cast<String>(),
      rows: rs
          .map((e) => RowData(
                id: e.id,
                index: e.index,
                cells: (jsonDecode(e.cellsJson) as List).cast<String>(),
                photos: (jsonDecode(e.photosJson) as List).cast<String>(),
                lat: e.lat,
                lng: e.lng,
                placeName: e.placeName,
              ))
          .toList(),
    );
  }

  // Rows
  Future<int> addRow(String sheetId, int index, List<String> cells) =>
      into(rows).insert(RowsCompanion(
        sheetId: Value(sheetId),
        index: Value(index),
        cellsJson: Value(jsonEncode(cells)),
      ));

  Future<void> updateRow(RowData r) async {
    await (update(rows)..where((t) => t.id.equals(r.id))).write(RowsCompanion(
      index: Value(r.index),
      cellsJson: Value(jsonEncode(r.cells)),
      photosJson: Value(jsonEncode(r.photos)),
      lat: Value(r.lat),
      lng: Value(r.lng),
      placeName: Value(r.placeName),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> deleteRow(int id) async =>
      (delete(rows)..where((t) => t.id.equals(id))).go();
}

// ---------- Tipos de dominio planos ----------
class SheetData {
  final String id, name;
  final int columns;
  final List<String> headers;
  final List<RowData> rows;
  SheetData(
      {required this.id,
      required this.name,
      required this.columns,
      required this.headers,
      required this.rows});
}

class RowData {
  final int id;
  int index;
  List<String> cells;
  List<String> photos;
  double? lat, lng;
  String? placeName;
  RowData({
    required this.id,
    required this.index,
    required this.cells,
    required this.photos,
    this.lat,
    this.lng,
    this.placeName,
  });
}

QueryExecutor _openConn() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'bitacora.db'));
    return NativeDatabase.createInBackground(file);
  });
}
