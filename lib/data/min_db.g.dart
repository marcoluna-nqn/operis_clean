// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'min_db.dart';

// ignore_for_file: type=lint
class $T1Table extends T1 with TableInfo<$T1Table, T1Data> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $T1Table(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  @override
  List<GeneratedColumn> get $columns => [id];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 't1';
  @override
  VerificationContext validateIntegrity(Insertable<T1Data> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  T1Data map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return T1Data(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
    );
  }

  @override
  $T1Table createAlias(String alias) {
    return $T1Table(attachedDatabase, alias);
  }
}

class T1Data extends DataClass implements Insertable<T1Data> {
  final int id;
  const T1Data({required this.id});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    return map;
  }

  T1Companion toCompanion(bool nullToAbsent) {
    return T1Companion(
      id: Value(id),
    );
  }

  factory T1Data.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return T1Data(
      id: serializer.fromJson<int>(json['id']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
    };
  }

  T1Data copyWith({int? id}) => T1Data(
        id: id ?? this.id,
      );
  T1Data copyWithCompanion(T1Companion data) {
    return T1Data(
      id: data.id.present ? data.id.value : this.id,
    );
  }

  @override
  String toString() {
    return (StringBuffer('T1Data(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => id.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is T1Data && other.id == this.id);
}

class T1Companion extends UpdateCompanion<T1Data> {
  final Value<int> id;
  const T1Companion({
    this.id = const Value.absent(),
  });
  T1Companion.insert({
    this.id = const Value.absent(),
  });
  static Insertable<T1Data> custom({
    Expression<int>? id,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
    });
  }

  T1Companion copyWith({Value<int>? id}) {
    return T1Companion(
      id: id ?? this.id,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('T1Companion(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }
}

abstract class _$MinDb extends GeneratedDatabase {
  _$MinDb(QueryExecutor e) : super(e);
  $MinDbManager get managers => $MinDbManager(this);
  late final $T1Table t1 = $T1Table(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [t1];
}

typedef $$T1TableCreateCompanionBuilder = T1Companion Function({
  Value<int> id,
});
typedef $$T1TableUpdateCompanionBuilder = T1Companion Function({
  Value<int> id,
});

class $$T1TableFilterComposer extends Composer<_$MinDb, $T1Table> {
  $$T1TableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));
}

class $$T1TableOrderingComposer extends Composer<_$MinDb, $T1Table> {
  $$T1TableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));
}

class $$T1TableAnnotationComposer extends Composer<_$MinDb, $T1Table> {
  $$T1TableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);
}

class $$T1TableTableManager extends RootTableManager<
    _$MinDb,
    $T1Table,
    T1Data,
    $$T1TableFilterComposer,
    $$T1TableOrderingComposer,
    $$T1TableAnnotationComposer,
    $$T1TableCreateCompanionBuilder,
    $$T1TableUpdateCompanionBuilder,
    (T1Data, BaseReferences<_$MinDb, $T1Table, T1Data>),
    T1Data,
    PrefetchHooks Function()> {
  $$T1TableTableManager(_$MinDb db, $T1Table table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$T1TableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$T1TableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$T1TableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
          }) =>
              T1Companion(
            id: id,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
          }) =>
              T1Companion.insert(
            id: id,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$T1TableProcessedTableManager = ProcessedTableManager<
    _$MinDb,
    $T1Table,
    T1Data,
    $$T1TableFilterComposer,
    $$T1TableOrderingComposer,
    $$T1TableAnnotationComposer,
    $$T1TableCreateCompanionBuilder,
    $$T1TableUpdateCompanionBuilder,
    (T1Data, BaseReferences<_$MinDb, $T1Table, T1Data>),
    T1Data,
    PrefetchHooks Function()>;

class $MinDbManager {
  final _$MinDb _db;
  $MinDbManager(this._db);
  $$T1TableTableManager get t1 => $$T1TableTableManager(_db, _db.t1);
}
