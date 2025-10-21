// lib/data/min_db.dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'min_db.g.dart';

class T1 extends Table {
  IntColumn get id => integer().autoIncrement()();
}

@DriftDatabase(tables: [T1])
class MinDb extends _$MinDb {
  MinDb() : super(NativeDatabase.memory());
  @override
  int get schemaVersion => 1;
}
