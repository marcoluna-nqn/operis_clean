// lib/db/app_db.dart
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_db.g.dart';

class KvStore extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {key};
}

class Entries extends Table {
  TextColumn get id => text()(); // UUID
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  TextColumn get payloadJson => text()(); // tu modelo en JSON
  TextColumn get checksum => text()();     // sha256(payloadJson)
  @override
  Set<Column> get primaryKey => {id};
}

class Photos extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get entryId =>
      text().references(Entries, #id, onDelete: KeyAction.cascade)();
  TextColumn get filePath => text()(); // ruta local (ej. <app>/media/….jpg)
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

/// Cola de trabajos offline (ej. subir/exportar/enviar)
class OutboxItems extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get kind => text()(); // p.ej. "export_xlsx" | "sync_api"
  TextColumn get payloadJson => text()(); // datos del trabajo
  TextColumn get status =>
      text().withDefault(const Constant('pending'))(); // pending|done|failed
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [KvStore, Entries, Photos, OutboxItems])
class AppDb extends _$AppDb {
  AppDb._(super.e);
  static AppDb? _instance;

  static Future<AppDb> instance() async {
    if (_instance != null) return _instance!;
    _instance = AppDb._(await _open());
    return _instance!;
  }

  static Future<QueryExecutor> _open() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'bitacora.db'));
    // Aseguramos carpeta media para fotos
    Directory(p.join(dir.path, 'media')).createSync(recursive: true);

    return NativeDatabase(
      file,
      setup: (rawDb) {
        // WAL + FK + sync robusto
        rawDb.execute('PRAGMA journal_mode = WAL;');
        rawDb.execute('PRAGMA foreign_keys = ON;');
        rawDb.execute('PRAGMA synchronous = NORMAL;');
      },
    );
  }

  @override
  int get schemaVersion => 1;

  // ----------------- KV helpers -----------------
  Future<void> kvSet(String key, String? value) async {
    await into(kvStore).insertOnConflictUpdate(
      KvStoreCompanion.insert(key: key, value: Value(value)),
    );
  }

  Future<String?> kvGet(String key) async {
    final row = await (select(kvStore)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  // ----------------- Entries API -----------------
  String _hash(String json) => sha256.convert(utf8.encode(json)).toString();

  Future<void> upsertEntry({
    required String id,
    required Map<String, dynamic> payload,
    bool deleted = false,
    DateTime? createdAt,
  }) async {
    final now = DateTime.now();
    final pj = jsonEncode(payload);
    final ck = _hash(pj);

    await transaction(() async {
      final exists = await (select(entries)..where((t) => t.id.equals(id))).getSingleOrNull();

      if (exists == null) {
        await into(entries).insert(
          EntriesCompanion.insert(
            id: id,
            createdAt: createdAt ?? now,
            updatedAt: now,
            deleted: Value(deleted),
            payloadJson: pj,
            checksum: ck,
          ),
        );
      } else {
        await (update(entries)..where((t) => t.id.equals(id))).write(
          EntriesCompanion(
            updatedAt: Value(now),
            deleted: Value(deleted),
            payloadJson: Value(pj),
            checksum: Value(ck),
          ),
        );
      }
    });
  }

  Future<Map<String, dynamic>?> getEntry(String id) async {
    final e = await (select(entries)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (e == null) return null;
    // Verificación simple de integridad
    if (_hash(e.payloadJson) != e.checksum) {
      // Podés loguear/alertar aquí
    }
    return jsonDecode(e.payloadJson) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listEntries({bool includeDeleted = false}) async {
    final q = select(entries);
    if (!includeDeleted) q.where((t) => t.deleted.equals(false));
    final rows = await q.get();
    return rows.map((e) => jsonDecode(e.payloadJson) as Map<String, dynamic>).toList();
  }

  // ----------------- Photos API -----------------
  Future<void> addPhoto({
    required String id,
    required String entryId,
    required String filePath,
  }) =>
      into(photos).insert(
        PhotosCompanion.insert(id: id, entryId: entryId, filePath: filePath),
        mode: InsertMode.insertOrReplace,
      );

  Future<List<String>> listPhotosPaths(String entryId) async {
    final rows = await (select(photos)..where((t) => t.entryId.equals(entryId))).get();
    return rows.map((r) => r.filePath).toList();
  }

  // ----------------- Outbox API -----------------
  Future<void> enqueueJob({
    required String id,
    required String kind,
    required Map<String, dynamic> payload,
    DateTime? scheduleAt,
  }) =>
      into(outboxItems).insert(
        OutboxItemsCompanion.insert(
          id: id,
          kind: kind,
          payloadJson: jsonEncode(payload),
          nextAttemptAt: Value(scheduleAt ?? DateTime.now()),
        ),
        mode: InsertMode.insertOrReplace,
      );

  Future<List<OutboxItem>> dueJobs(DateTime now) =>
      (select(outboxItems)
        ..where((t) => t.status.equals('pending') & t.nextAttemptAt.isSmallerOrEqualValue(now))
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  Future<void> markJobDone(String id) =>
      (update(outboxItems)..where((t) => t.id.equals(id))).write(const OutboxItemsCompanion(status: Value('done')));

  Future<void> rescheduleJob(String id, int attempts, Duration backoff) =>
      (update(outboxItems)..where((t) => t.id.equals(id))).write(
        OutboxItemsCompanion(
          attempts: Value(attempts + 1),
          nextAttemptAt: Value(DateTime.now().add(backoff)),
          status: const Value('pending'),
        ),
      );

  Future<void> markJobFailed(String id) =>
      (update(outboxItems)..where((t) => t.id.equals(id))).write(const OutboxItemsCompanion(status: Value('failed')));

  // ----------------- Paths útiles -----------------
  static Future<File> dbFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'bitacora.db'));
  }

  static Future<Directory> mediaDir() async {
    final dir = await getApplicationSupportDirectory();
    return Directory(p.join(dir.path, 'media'));
  }
}
