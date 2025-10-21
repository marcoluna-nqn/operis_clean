// lib/services/anomaly_service.dart
import 'package:flutter/foundation.dart';

enum AnomalySeverity { info, warning, error, critical }

enum AnomalyCode {
  unknown,
  emptyHeader,
  duplicateHeader,
  emptyRow,
  gpsMissing,
  tooManyPhotos,
  cellTooLong,
  ioFailure,
  speechLowConfidence,
}

@immutable
class AnomalyFlag with DiagnosticableTreeMixin {
  // 1) Quitar `const` del constructor porque usamos DateTime.now()/fromMillisecondsSinceEpoch
  AnomalyFlag({
    required this.code,
    required this.severity,
    required this.message,
    this.hint,
    this.sheetId,
    this.rowIndex,
    this.colIndex,
    this.photoIndex,
    this.lat,
    this.lng,
    DateTime? createdAt,
    this.meta = const {},
  }) : createdAt = createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String message;
  final String? hint;
  final AnomalyCode code;
  final AnomalySeverity severity;

  final String? sheetId;
  final int? rowIndex;
  final int? colIndex;
  final int? photoIndex;
  final double? lat;
  final double? lng;

  final DateTime createdAt;
  final Map<String, Object?> meta;

  factory AnomalyFlag.info(
      String message, {
        AnomalyCode code = AnomalyCode.unknown,
        String? hint,
        String? sheetId,
        int? rowIndex,
        int? colIndex,
        int? photoIndex,
        double? lat,
        double? lng,
        DateTime? createdAt,
        Map<String, Object?> meta = const {},
      }) =>
      AnomalyFlag(
        code: code,
        severity: AnomalySeverity.info,
        message: message,
        hint: hint,
        sheetId: sheetId,
        rowIndex: rowIndex,
        colIndex: colIndex,
        photoIndex: photoIndex,
        lat: lat,
        lng: lng,
        createdAt: createdAt,
        meta: meta,
      );

  factory AnomalyFlag.warn(
      String message, {
        AnomalyCode code = AnomalyCode.unknown,
        String? hint,
        String? sheetId,
        int? rowIndex,
        int? colIndex,
        int? photoIndex,
        double? lat,
        double? lng,
        DateTime? createdAt,
        Map<String, Object?> meta = const {},
      }) =>
      AnomalyFlag(
        code: code,
        severity: AnomalySeverity.warning,
        message: message,
        hint: hint,
        sheetId: sheetId,
        rowIndex: rowIndex,
        colIndex: colIndex,
        photoIndex: photoIndex,
        lat: lat,
        lng: lng,
        createdAt: createdAt,
        meta: meta,
      );

  factory AnomalyFlag.error(
      String message, {
        AnomalyCode code = AnomalyCode.unknown,
        String? hint,
        String? sheetId,
        int? rowIndex,
        int? colIndex,
        int? photoIndex,
        double? lat,
        double? lng,
        DateTime? createdAt,
        Map<String, Object?> meta = const {},
      }) =>
      AnomalyFlag(
        code: code,
        severity: AnomalySeverity.error,
        message: message,
        hint: hint,
        sheetId: sheetId,
        rowIndex: rowIndex,
        colIndex: colIndex,
        photoIndex: photoIndex,
        lat: lat,
        lng: lng,
        createdAt: createdAt,
        meta: meta,
      );

  AnomalyFlag copyWith({
    String? message,
    String? hint,
    AnomalyCode? code,
    AnomalySeverity? severity,
    String? sheetId,
    int? rowIndex,
    int? colIndex,
    int? photoIndex,
    double? lat,
    double? lng,
    DateTime? createdAt,
    Map<String, Object?>? meta,
  }) {
    return AnomalyFlag(
      message: message ?? this.message,
      hint: hint ?? this.hint,
      code: code ?? this.code,
      severity: severity ?? this.severity,
      sheetId: sheetId ?? this.sheetId,
      rowIndex: rowIndex ?? this.rowIndex,
      colIndex: colIndex ?? this.colIndex,
      photoIndex: photoIndex ?? this.photoIndex,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      createdAt: createdAt ?? this.createdAt,
      meta: meta ?? this.meta,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'message': message,
    'hint': hint,
    'code': code.name,
    'severity': severity.name,
    'sheetId': sheetId,
    'rowIndex': rowIndex,
    'colIndex': colIndex,
    'photoIndex': photoIndex,
    'lat': lat,
    'lng': lng,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'meta': meta,
  };

  factory AnomalyFlag.fromJson(Map<String, Object?> json) => AnomalyFlag(
    message: (json['message'] as String?) ?? '',
    hint: json['hint'] as String?,
    code: AnomalyCode.values.firstWhere(
          (e) => e.name == json['code'],
      orElse: () => AnomalyCode.unknown,
    ),
    severity: AnomalySeverity.values.firstWhere(
          (e) => e.name == json['severity'],
      orElse: () => AnomalySeverity.info,
    ),
    sheetId: json['sheetId'] as String?,
    rowIndex: json['rowIndex'] as int?,
    colIndex: json['colIndex'] as int?,
    photoIndex: json['photoIndex'] as int?,
    lat: (json['lat'] as num?)?.toDouble(),
    lng: (json['lng'] as num?)?.toDouble(),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (json['createdAt'] as int?) ?? 0,
    ),
    meta: (json['meta'] as Map?)?.cast<String, Object?>() ?? const {},
  );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(EnumProperty('code', code))
      ..add(EnumProperty('severity', severity))
      ..add(StringProperty('message', message))
      ..add(StringProperty('hint', hint))
      ..add(StringProperty('sheetId', sheetId))
      ..add(IntProperty('rowIndex', rowIndex))
      ..add(IntProperty('colIndex', colIndex))
      ..add(IntProperty('photoIndex', photoIndex))
      ..add(DoubleProperty('lat', lat))
      ..add(DoubleProperty('lng', lng))
      ..add(DiagnosticsProperty<DateTime>('createdAt', createdAt))
      ..add(DiagnosticsProperty<Map<String, Object?>>('meta', meta));
  }

  @override
  bool operator ==(Object other) {
    return other is AnomalyFlag &&
        other.message == message &&
        other.hint == hint &&
        other.code == code &&
        other.severity == severity &&
        other.sheetId == sheetId &&
        other.rowIndex == rowIndex &&
        other.colIndex == colIndex &&
        other.photoIndex == photoIndex &&
        other.lat == lat &&
        other.lng == lng &&
        other.createdAt == createdAt &&
        mapEquals(other.meta, meta);
  }

  @override
  int get hashCode => Object.hash(
    message,
    hint,
    code,
    severity,
    sheetId,
    rowIndex,
    colIndex,
    photoIndex,
    lat,
    lng,
    createdAt,
    Object.hashAllUnordered(meta.entries),
  );
}

@immutable
class AnomalySet extends Iterable<AnomalyFlag> {
  const AnomalySet(this._items);
  final List<AnomalyFlag> _items;

  // 2) Para que el `const` de la estática sea válido,
  //    la lista literal también debe ser const.
  static const empty = AnomalySet(<AnomalyFlag>[]);

  @override
  Iterator<AnomalyFlag> get iterator => _items.iterator;

  @override
  int get length => _items.length;

  bool get hasErrors =>
      _items.any((a) => a.severity == AnomalySeverity.error || a.severity == AnomalySeverity.critical);

  int countWhere(bool Function(AnomalyFlag) test) => _items.where(test).length;

  AnomalySet whereSeverity(AnomalySeverity s) =>
      AnomalySet(_items.where((a) => a.severity == s).toList(growable: false));

  AnomalySet whereCode(AnomalyCode c) =>
      AnomalySet(_items.where((a) => a.code == c).toList(growable: false));

  List<AnomalyFlag> toListSafe() => List<AnomalyFlag>.unmodifiable(_items);
}

abstract class AnomalyService {
  Future<AnomalySet> find(dynamic context);
}

typedef AnomalyRule = List<AnomalyFlag> Function(dynamic context);

class DefaultAnomalyService implements AnomalyService {
  const DefaultAnomalyService({this.rules = const []});
  final List<AnomalyRule> rules;

  @override
  Future<AnomalySet> find(dynamic context) async {
    if (rules.isEmpty) return AnomalySet.empty;
    final collected = <AnomalyFlag>[];
    for (final rule in rules) {
      try {
        collected.addAll(rule(context));
      } catch (e, st) {
        collected.add(
          AnomalyFlag.error(
            'Regla de anomalías falló',
            code: AnomalyCode.ioFailure,
            hint: 'Revisar logs',
            meta: {'error': e.toString(), 'stack': st.toString()},
          ),
        );
      }
    }
    return AnomalySet(List<AnomalyFlag>.unmodifiable(collected));
  }
}

class AnomalyRules {
  const AnomalyRules._();

  static AnomalyRule maxPhotosPerRow({
    required int Function(dynamic ctx) rowsCount,
    required int Function(dynamic ctx, int row) photosCountOfRow,
    required int maxPhotos,
    String? sheetId,
  }) {
    return (ctx) {
      final out = <AnomalyFlag>[];
      final rows = rowsCount(ctx);
      for (var r = 0; r < rows; r++) {
        final n = photosCountOfRow(ctx, r);
        if (n > maxPhotos) {
          out.add(AnomalyFlag.warn(
            'Fila ${r + 1}: $n fotos (máximo $maxPhotos)',
            code: AnomalyCode.tooManyPhotos,
            sheetId: sheetId,
            rowIndex: r,
            hint: 'Eliminá o mové fotos a otras filas.',
            meta: {'count': n, 'limit': maxPhotos},
          ));
        }
      }
      return out;
    };
  }

  static AnomalyRule emptyHeaders({
    required int headersCount,
    required String Function(int i) headerAt,
    String? sheetId,
  }) {
    return (_) {
      final out = <AnomalyFlag>[];
      for (var i = 0; i < headersCount; i++) {
        if (headerAt(i).trim().isEmpty) {
          out.add(AnomalyFlag.info(
            'Encabezado ${i + 1} vacío',
            code: AnomalyCode.emptyHeader,
            sheetId: sheetId,
            colIndex: i,
            hint: 'Tocá el encabezado para nombrarlo.',
          ));
        }
      }
      return out;
    };
  }
}
