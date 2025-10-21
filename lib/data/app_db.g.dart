// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_db.dart';

// ignore_for_file: type=lint
class $SheetsTable extends Sheets with TableInfo<$SheetsTable, Sheet> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SheetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: Constant('Bitácora'));
  static const VerificationMeta _columnsMeta =
      const VerificationMeta('columns');
  @override
  late final GeneratedColumn<int> columns = GeneratedColumn<int>(
      'columns', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(5));
  static const VerificationMeta _headersJsonMeta =
      const VerificationMeta('headersJson');
  @override
  late final GeneratedColumn<String> headersJson = GeneratedColumn<String>(
      'headers_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, columns, headersJson, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sheets';
  @override
  VerificationContext validateIntegrity(Insertable<Sheet> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    }
    if (data.containsKey('columns')) {
      context.handle(_columnsMeta,
          columns.isAcceptableOrUnknown(data['columns']!, _columnsMeta));
    }
    if (data.containsKey('headers_json')) {
      context.handle(
          _headersJsonMeta,
          headersJson.isAcceptableOrUnknown(
              data['headers_json']!, _headersJsonMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Sheet map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Sheet(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      columns: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}columns'])!,
      headersJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}headers_json'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $SheetsTable createAlias(String alias) {
    return $SheetsTable(attachedDatabase, alias);
  }
}

class Sheet extends DataClass implements Insertable<Sheet> {
  final String id;
  final String name;
  final int columns;
  final String headersJson;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Sheet(
      {required this.id,
      required this.name,
      required this.columns,
      required this.headersJson,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['columns'] = Variable<int>(columns);
    map['headers_json'] = Variable<String>(headersJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SheetsCompanion toCompanion(bool nullToAbsent) {
    return SheetsCompanion(
      id: Value(id),
      name: Value(name),
      columns: Value(columns),
      headersJson: Value(headersJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Sheet.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Sheet(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      columns: serializer.fromJson<int>(json['columns']),
      headersJson: serializer.fromJson<String>(json['headersJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'columns': serializer.toJson<int>(columns),
      'headersJson': serializer.toJson<String>(headersJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Sheet copyWith(
          {String? id,
          String? name,
          int? columns,
          String? headersJson,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Sheet(
        id: id ?? this.id,
        name: name ?? this.name,
        columns: columns ?? this.columns,
        headersJson: headersJson ?? this.headersJson,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Sheet copyWithCompanion(SheetsCompanion data) {
    return Sheet(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      columns: data.columns.present ? data.columns.value : this.columns,
      headersJson:
          data.headersJson.present ? data.headersJson.value : this.headersJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Sheet(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('columns: $columns, ')
          ..write('headersJson: $headersJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, columns, headersJson, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Sheet &&
          other.id == this.id &&
          other.name == this.name &&
          other.columns == this.columns &&
          other.headersJson == this.headersJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SheetsCompanion extends UpdateCompanion<Sheet> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> columns;
  final Value<String> headersJson;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SheetsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.columns = const Value.absent(),
    this.headersJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SheetsCompanion.insert({
    required String id,
    this.name = const Value.absent(),
    this.columns = const Value.absent(),
    this.headersJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<Sheet> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? columns,
    Expression<String>? headersJson,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (columns != null) 'columns': columns,
      if (headersJson != null) 'headers_json': headersJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SheetsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<int>? columns,
      Value<String>? headersJson,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return SheetsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      columns: columns ?? this.columns,
      headersJson: headersJson ?? this.headersJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (columns.present) {
      map['columns'] = Variable<int>(columns.value);
    }
    if (headersJson.present) {
      map['headers_json'] = Variable<String>(headersJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SheetsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('columns: $columns, ')
          ..write('headersJson: $headersJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RowsTable extends Rows with TableInfo<$RowsTable, Row> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _sheetIdMeta =
      const VerificationMeta('sheetId');
  @override
  late final GeneratedColumn<String> sheetId = GeneratedColumn<String>(
      'sheet_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES sheets (id)'));
  static const VerificationMeta _indexMeta = const VerificationMeta('index');
  @override
  late final GeneratedColumn<int> index = GeneratedColumn<int>(
      'index', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _cellsJsonMeta =
      const VerificationMeta('cellsJson');
  @override
  late final GeneratedColumn<String> cellsJson = GeneratedColumn<String>(
      'cells_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _photosJsonMeta =
      const VerificationMeta('photosJson');
  @override
  late final GeneratedColumn<String> photosJson = GeneratedColumn<String>(
      'photos_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
      'lat', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _lngMeta = const VerificationMeta('lng');
  @override
  late final GeneratedColumn<double> lng = GeneratedColumn<double>(
      'lng', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _placeNameMeta =
      const VerificationMeta('placeName');
  @override
  late final GeneratedColumn<String> placeName = GeneratedColumn<String>(
      'place_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        sheetId,
        index,
        cellsJson,
        photosJson,
        lat,
        lng,
        placeName,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rows';
  @override
  VerificationContext validateIntegrity(Insertable<Row> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('sheet_id')) {
      context.handle(_sheetIdMeta,
          sheetId.isAcceptableOrUnknown(data['sheet_id']!, _sheetIdMeta));
    } else if (isInserting) {
      context.missing(_sheetIdMeta);
    }
    if (data.containsKey('index')) {
      context.handle(
          _indexMeta, index.isAcceptableOrUnknown(data['index']!, _indexMeta));
    } else if (isInserting) {
      context.missing(_indexMeta);
    }
    if (data.containsKey('cells_json')) {
      context.handle(_cellsJsonMeta,
          cellsJson.isAcceptableOrUnknown(data['cells_json']!, _cellsJsonMeta));
    } else if (isInserting) {
      context.missing(_cellsJsonMeta);
    }
    if (data.containsKey('photos_json')) {
      context.handle(
          _photosJsonMeta,
          photosJson.isAcceptableOrUnknown(
              data['photos_json']!, _photosJsonMeta));
    }
    if (data.containsKey('lat')) {
      context.handle(
          _latMeta, lat.isAcceptableOrUnknown(data['lat']!, _latMeta));
    }
    if (data.containsKey('lng')) {
      context.handle(
          _lngMeta, lng.isAcceptableOrUnknown(data['lng']!, _lngMeta));
    }
    if (data.containsKey('place_name')) {
      context.handle(_placeNameMeta,
          placeName.isAcceptableOrUnknown(data['place_name']!, _placeNameMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Row map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Row(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      sheetId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sheet_id'])!,
      index: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}index'])!,
      cellsJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cells_json'])!,
      photosJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}photos_json'])!,
      lat: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}lat']),
      lng: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}lng']),
      placeName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}place_name']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $RowsTable createAlias(String alias) {
    return $RowsTable(attachedDatabase, alias);
  }
}

class Row extends DataClass implements Insertable<Row> {
  final int id;
  final String sheetId;
  final int index;
  final String cellsJson;
  final String photosJson;
  final double? lat;
  final double? lng;
  final String? placeName;
  final DateTime updatedAt;
  const Row(
      {required this.id,
      required this.sheetId,
      required this.index,
      required this.cellsJson,
      required this.photosJson,
      this.lat,
      this.lng,
      this.placeName,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['sheet_id'] = Variable<String>(sheetId);
    map['index'] = Variable<int>(index);
    map['cells_json'] = Variable<String>(cellsJson);
    map['photos_json'] = Variable<String>(photosJson);
    if (!nullToAbsent || lat != null) {
      map['lat'] = Variable<double>(lat);
    }
    if (!nullToAbsent || lng != null) {
      map['lng'] = Variable<double>(lng);
    }
    if (!nullToAbsent || placeName != null) {
      map['place_name'] = Variable<String>(placeName);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  RowsCompanion toCompanion(bool nullToAbsent) {
    return RowsCompanion(
      id: Value(id),
      sheetId: Value(sheetId),
      index: Value(index),
      cellsJson: Value(cellsJson),
      photosJson: Value(photosJson),
      lat: lat == null && nullToAbsent ? const Value.absent() : Value(lat),
      lng: lng == null && nullToAbsent ? const Value.absent() : Value(lng),
      placeName: placeName == null && nullToAbsent
          ? const Value.absent()
          : Value(placeName),
      updatedAt: Value(updatedAt),
    );
  }

  factory Row.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Row(
      id: serializer.fromJson<int>(json['id']),
      sheetId: serializer.fromJson<String>(json['sheetId']),
      index: serializer.fromJson<int>(json['index']),
      cellsJson: serializer.fromJson<String>(json['cellsJson']),
      photosJson: serializer.fromJson<String>(json['photosJson']),
      lat: serializer.fromJson<double?>(json['lat']),
      lng: serializer.fromJson<double?>(json['lng']),
      placeName: serializer.fromJson<String?>(json['placeName']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sheetId': serializer.toJson<String>(sheetId),
      'index': serializer.toJson<int>(index),
      'cellsJson': serializer.toJson<String>(cellsJson),
      'photosJson': serializer.toJson<String>(photosJson),
      'lat': serializer.toJson<double?>(lat),
      'lng': serializer.toJson<double?>(lng),
      'placeName': serializer.toJson<String?>(placeName),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Row copyWith(
          {int? id,
          String? sheetId,
          int? index,
          String? cellsJson,
          String? photosJson,
          Value<double?> lat = const Value.absent(),
          Value<double?> lng = const Value.absent(),
          Value<String?> placeName = const Value.absent(),
          DateTime? updatedAt}) =>
      Row(
        id: id ?? this.id,
        sheetId: sheetId ?? this.sheetId,
        index: index ?? this.index,
        cellsJson: cellsJson ?? this.cellsJson,
        photosJson: photosJson ?? this.photosJson,
        lat: lat.present ? lat.value : this.lat,
        lng: lng.present ? lng.value : this.lng,
        placeName: placeName.present ? placeName.value : this.placeName,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Row copyWithCompanion(RowsCompanion data) {
    return Row(
      id: data.id.present ? data.id.value : this.id,
      sheetId: data.sheetId.present ? data.sheetId.value : this.sheetId,
      index: data.index.present ? data.index.value : this.index,
      cellsJson: data.cellsJson.present ? data.cellsJson.value : this.cellsJson,
      photosJson:
          data.photosJson.present ? data.photosJson.value : this.photosJson,
      lat: data.lat.present ? data.lat.value : this.lat,
      lng: data.lng.present ? data.lng.value : this.lng,
      placeName: data.placeName.present ? data.placeName.value : this.placeName,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Row(')
          ..write('id: $id, ')
          ..write('sheetId: $sheetId, ')
          ..write('index: $index, ')
          ..write('cellsJson: $cellsJson, ')
          ..write('photosJson: $photosJson, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('placeName: $placeName, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, sheetId, index, cellsJson, photosJson,
      lat, lng, placeName, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Row &&
          other.id == this.id &&
          other.sheetId == this.sheetId &&
          other.index == this.index &&
          other.cellsJson == this.cellsJson &&
          other.photosJson == this.photosJson &&
          other.lat == this.lat &&
          other.lng == this.lng &&
          other.placeName == this.placeName &&
          other.updatedAt == this.updatedAt);
}

class RowsCompanion extends UpdateCompanion<Row> {
  final Value<int> id;
  final Value<String> sheetId;
  final Value<int> index;
  final Value<String> cellsJson;
  final Value<String> photosJson;
  final Value<double?> lat;
  final Value<double?> lng;
  final Value<String?> placeName;
  final Value<DateTime> updatedAt;
  const RowsCompanion({
    this.id = const Value.absent(),
    this.sheetId = const Value.absent(),
    this.index = const Value.absent(),
    this.cellsJson = const Value.absent(),
    this.photosJson = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.placeName = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  RowsCompanion.insert({
    this.id = const Value.absent(),
    required String sheetId,
    required int index,
    required String cellsJson,
    this.photosJson = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.placeName = const Value.absent(),
    this.updatedAt = const Value.absent(),
  })  : sheetId = Value(sheetId),
        index = Value(index),
        cellsJson = Value(cellsJson);
  static Insertable<Row> custom({
    Expression<int>? id,
    Expression<String>? sheetId,
    Expression<int>? index,
    Expression<String>? cellsJson,
    Expression<String>? photosJson,
    Expression<double>? lat,
    Expression<double>? lng,
    Expression<String>? placeName,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sheetId != null) 'sheet_id': sheetId,
      if (index != null) 'index': index,
      if (cellsJson != null) 'cells_json': cellsJson,
      if (photosJson != null) 'photos_json': photosJson,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (placeName != null) 'place_name': placeName,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  RowsCompanion copyWith(
      {Value<int>? id,
      Value<String>? sheetId,
      Value<int>? index,
      Value<String>? cellsJson,
      Value<String>? photosJson,
      Value<double?>? lat,
      Value<double?>? lng,
      Value<String?>? placeName,
      Value<DateTime>? updatedAt}) {
    return RowsCompanion(
      id: id ?? this.id,
      sheetId: sheetId ?? this.sheetId,
      index: index ?? this.index,
      cellsJson: cellsJson ?? this.cellsJson,
      photosJson: photosJson ?? this.photosJson,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      placeName: placeName ?? this.placeName,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sheetId.present) {
      map['sheet_id'] = Variable<String>(sheetId.value);
    }
    if (index.present) {
      map['index'] = Variable<int>(index.value);
    }
    if (cellsJson.present) {
      map['cells_json'] = Variable<String>(cellsJson.value);
    }
    if (photosJson.present) {
      map['photos_json'] = Variable<String>(photosJson.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lng.present) {
      map['lng'] = Variable<double>(lng.value);
    }
    if (placeName.present) {
      map['place_name'] = Variable<String>(placeName.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RowsCompanion(')
          ..write('id: $id, ')
          ..write('sheetId: $sheetId, ')
          ..write('index: $index, ')
          ..write('cellsJson: $cellsJson, ')
          ..write('photosJson: $photosJson, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('placeName: $placeName, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDb extends GeneratedDatabase {
  _$AppDb(QueryExecutor e) : super(e);
  $AppDbManager get managers => $AppDbManager(this);
  late final $SheetsTable sheets = $SheetsTable(this);
  late final $RowsTable rows = $RowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [sheets, rows];
}

typedef $$SheetsTableCreateCompanionBuilder = SheetsCompanion Function({
  required String id,
  Value<String> name,
  Value<int> columns,
  Value<String> headersJson,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});
typedef $$SheetsTableUpdateCompanionBuilder = SheetsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<int> columns,
  Value<String> headersJson,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

final class $$SheetsTableReferences
    extends BaseReferences<_$AppDb, $SheetsTable, Sheet> {
  $$SheetsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$RowsTable, List<Row>> _rowsRefsTable(
          _$AppDb db) =>
      MultiTypedResultKey.fromTable(db.rows,
          aliasName: $_aliasNameGenerator(db.sheets.id, db.rows.sheetId));

  $$RowsTableProcessedTableManager get rowsRefs {
    final manager = $$RowsTableTableManager($_db, $_db.rows)
        .filter((f) => f.sheetId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_rowsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$SheetsTableFilterComposer extends Composer<_$AppDb, $SheetsTable> {
  $$SheetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get columns => $composableBuilder(
      column: $table.columns, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get headersJson => $composableBuilder(
      column: $table.headersJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  Expression<bool> rowsRefs(
      Expression<bool> Function($$RowsTableFilterComposer f) f) {
    final $$RowsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.rows,
        getReferencedColumn: (t) => t.sheetId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RowsTableFilterComposer(
              $db: $db,
              $table: $db.rows,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$SheetsTableOrderingComposer extends Composer<_$AppDb, $SheetsTable> {
  $$SheetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get columns => $composableBuilder(
      column: $table.columns, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get headersJson => $composableBuilder(
      column: $table.headersJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$SheetsTableAnnotationComposer extends Composer<_$AppDb, $SheetsTable> {
  $$SheetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get columns =>
      $composableBuilder(column: $table.columns, builder: (column) => column);

  GeneratedColumn<String> get headersJson => $composableBuilder(
      column: $table.headersJson, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> rowsRefs<T extends Object>(
      Expression<T> Function($$RowsTableAnnotationComposer a) f) {
    final $$RowsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.rows,
        getReferencedColumn: (t) => t.sheetId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RowsTableAnnotationComposer(
              $db: $db,
              $table: $db.rows,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$SheetsTableTableManager extends RootTableManager<
    _$AppDb,
    $SheetsTable,
    Sheet,
    $$SheetsTableFilterComposer,
    $$SheetsTableOrderingComposer,
    $$SheetsTableAnnotationComposer,
    $$SheetsTableCreateCompanionBuilder,
    $$SheetsTableUpdateCompanionBuilder,
    (Sheet, $$SheetsTableReferences),
    Sheet,
    PrefetchHooks Function({bool rowsRefs})> {
  $$SheetsTableTableManager(_$AppDb db, $SheetsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SheetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SheetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SheetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> columns = const Value.absent(),
            Value<String> headersJson = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SheetsCompanion(
            id: id,
            name: name,
            columns: columns,
            headersJson: headersJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String> name = const Value.absent(),
            Value<int> columns = const Value.absent(),
            Value<String> headersJson = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SheetsCompanion.insert(
            id: id,
            name: name,
            columns: columns,
            headersJson: headersJson,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$SheetsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({rowsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (rowsRefs) db.rows],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (rowsRefs)
                    await $_getPrefetchedData<Sheet, $SheetsTable, Row>(
                        currentTable: table,
                        referencedTable:
                            $$SheetsTableReferences._rowsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$SheetsTableReferences(db, table, p0).rowsRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.sheetId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$SheetsTableProcessedTableManager = ProcessedTableManager<
    _$AppDb,
    $SheetsTable,
    Sheet,
    $$SheetsTableFilterComposer,
    $$SheetsTableOrderingComposer,
    $$SheetsTableAnnotationComposer,
    $$SheetsTableCreateCompanionBuilder,
    $$SheetsTableUpdateCompanionBuilder,
    (Sheet, $$SheetsTableReferences),
    Sheet,
    PrefetchHooks Function({bool rowsRefs})>;
typedef $$RowsTableCreateCompanionBuilder = RowsCompanion Function({
  Value<int> id,
  required String sheetId,
  required int index,
  required String cellsJson,
  Value<String> photosJson,
  Value<double?> lat,
  Value<double?> lng,
  Value<String?> placeName,
  Value<DateTime> updatedAt,
});
typedef $$RowsTableUpdateCompanionBuilder = RowsCompanion Function({
  Value<int> id,
  Value<String> sheetId,
  Value<int> index,
  Value<String> cellsJson,
  Value<String> photosJson,
  Value<double?> lat,
  Value<double?> lng,
  Value<String?> placeName,
  Value<DateTime> updatedAt,
});

final class $$RowsTableReferences
    extends BaseReferences<_$AppDb, $RowsTable, Row> {
  $$RowsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SheetsTable _sheetIdTable(_$AppDb db) => db.sheets
      .createAlias($_aliasNameGenerator(db.rows.sheetId, db.sheets.id));

  $$SheetsTableProcessedTableManager get sheetId {
    final $_column = $_itemColumn<String>('sheet_id')!;

    final manager = $$SheetsTableTableManager($_db, $_db.sheets)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sheetIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$RowsTableFilterComposer extends Composer<_$AppDb, $RowsTable> {
  $$RowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get index => $composableBuilder(
      column: $table.index, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cellsJson => $composableBuilder(
      column: $table.cellsJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get photosJson => $composableBuilder(
      column: $table.photosJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get lat => $composableBuilder(
      column: $table.lat, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get lng => $composableBuilder(
      column: $table.lng, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get placeName => $composableBuilder(
      column: $table.placeName, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  $$SheetsTableFilterComposer get sheetId {
    final $$SheetsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sheetId,
        referencedTable: $db.sheets,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SheetsTableFilterComposer(
              $db: $db,
              $table: $db.sheets,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$RowsTableOrderingComposer extends Composer<_$AppDb, $RowsTable> {
  $$RowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get index => $composableBuilder(
      column: $table.index, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cellsJson => $composableBuilder(
      column: $table.cellsJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get photosJson => $composableBuilder(
      column: $table.photosJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get lat => $composableBuilder(
      column: $table.lat, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get lng => $composableBuilder(
      column: $table.lng, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get placeName => $composableBuilder(
      column: $table.placeName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  $$SheetsTableOrderingComposer get sheetId {
    final $$SheetsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sheetId,
        referencedTable: $db.sheets,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SheetsTableOrderingComposer(
              $db: $db,
              $table: $db.sheets,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$RowsTableAnnotationComposer extends Composer<_$AppDb, $RowsTable> {
  $$RowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get index =>
      $composableBuilder(column: $table.index, builder: (column) => column);

  GeneratedColumn<String> get cellsJson =>
      $composableBuilder(column: $table.cellsJson, builder: (column) => column);

  GeneratedColumn<String> get photosJson => $composableBuilder(
      column: $table.photosJson, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lng =>
      $composableBuilder(column: $table.lng, builder: (column) => column);

  GeneratedColumn<String> get placeName =>
      $composableBuilder(column: $table.placeName, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$SheetsTableAnnotationComposer get sheetId {
    final $$SheetsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sheetId,
        referencedTable: $db.sheets,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SheetsTableAnnotationComposer(
              $db: $db,
              $table: $db.sheets,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$RowsTableTableManager extends RootTableManager<
    _$AppDb,
    $RowsTable,
    Row,
    $$RowsTableFilterComposer,
    $$RowsTableOrderingComposer,
    $$RowsTableAnnotationComposer,
    $$RowsTableCreateCompanionBuilder,
    $$RowsTableUpdateCompanionBuilder,
    (Row, $$RowsTableReferences),
    Row,
    PrefetchHooks Function({bool sheetId})> {
  $$RowsTableTableManager(_$AppDb db, $RowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> sheetId = const Value.absent(),
            Value<int> index = const Value.absent(),
            Value<String> cellsJson = const Value.absent(),
            Value<String> photosJson = const Value.absent(),
            Value<double?> lat = const Value.absent(),
            Value<double?> lng = const Value.absent(),
            Value<String?> placeName = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              RowsCompanion(
            id: id,
            sheetId: sheetId,
            index: index,
            cellsJson: cellsJson,
            photosJson: photosJson,
            lat: lat,
            lng: lng,
            placeName: placeName,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String sheetId,
            required int index,
            required String cellsJson,
            Value<String> photosJson = const Value.absent(),
            Value<double?> lat = const Value.absent(),
            Value<double?> lng = const Value.absent(),
            Value<String?> placeName = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              RowsCompanion.insert(
            id: id,
            sheetId: sheetId,
            index: index,
            cellsJson: cellsJson,
            photosJson: photosJson,
            lat: lat,
            lng: lng,
            placeName: placeName,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$RowsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({sheetId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (sheetId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.sheetId,
                    referencedTable: $$RowsTableReferences._sheetIdTable(db),
                    referencedColumn:
                        $$RowsTableReferences._sheetIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$RowsTableProcessedTableManager = ProcessedTableManager<
    _$AppDb,
    $RowsTable,
    Row,
    $$RowsTableFilterComposer,
    $$RowsTableOrderingComposer,
    $$RowsTableAnnotationComposer,
    $$RowsTableCreateCompanionBuilder,
    $$RowsTableUpdateCompanionBuilder,
    (Row, $$RowsTableReferences),
    Row,
    PrefetchHooks Function({bool sheetId})>;

class $AppDbManager {
  final _$AppDb _db;
  $AppDbManager(this._db);
  $$SheetsTableTableManager get sheets =>
      $$SheetsTableTableManager(_db, _db.sheets);
  $$RowsTableTableManager get rows => $$RowsTableTableManager(_db, _db.rows);
}
