// lib/models/measurement.dart

/// Modelo base de una medición/registro de una planilla.
class Measurement {
  final int? id; // id interno (DB)
  final int sheetId; // id de la planilla a la que pertenece
  final String progresiva; // “progresiva” / cadena / pk
  final String? seccion; // opcional
  final String? estructura; // opcional

  // Campos usados por EditMeasurementSheet:
  final double? ohm1m; // resistencia a 1 m (Ω)
  final double? ohm3m; // resistencia a 3 m (Ω)
  final double? latitude; // -90..90
  final double? longitude; // -180..180
  final String observations; // notas (no nulo para poder .trim())
  final DateTime createdAt; // fecha de creación

  const Measurement({
    this.id,
    required this.sheetId,
    required this.progresiva,
    this.seccion,
    this.estructura,
    this.ohm1m,
    this.ohm3m,
    this.latitude,
    this.longitude,
    this.observations = '',
    required this.createdAt,
  });

  /// Crea un registro “vacío” útil para formularios de alta.
  factory Measurement.empty({required int sheetId}) => Measurement(
        id: null,
        sheetId: sheetId,
        progresiva: '',
        seccion: null,
        estructura: null,
        ohm1m: null,
        ohm3m: null,
        latitude: null,
        longitude: null,
        observations: '',
        createdAt: DateTime.now(),
      );

  Measurement copyWith({
    int? id,
    int? sheetId,
    String? progresiva,
    String? seccion,
    String? estructura,
    double? ohm1m,
    double? ohm3m,
    double? latitude,
    double? longitude,
    String? observations,
    DateTime? createdAt,
  }) {
    return Measurement(
      id: id ?? this.id,
      sheetId: sheetId ?? this.sheetId,
      progresiva: progresiva ?? this.progresiva,
      seccion: seccion ?? this.seccion,
      estructura: estructura ?? this.estructura,
      ohm1m: ohm1m ?? this.ohm1m,
      ohm3m: ohm3m ?? this.ohm3m,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      observations: observations ?? this.observations,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // --------- (De)serialización sencilla ---------

  Map<String, Object?> toMap() => {
        'id': id,
        'sheetId': sheetId,
        'progresiva': progresiva,
        'seccion': seccion,
        'estructura': estructura,
        'ohm1m': ohm1m,
        'ohm3m': ohm3m,
        'latitude': latitude,
        'longitude': longitude,
        'observations': observations,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Measurement.fromMap(Map<String, Object?> map) => Measurement(
        id: map['id'] as int?,
        sheetId: (map['sheetId'] as num).toInt(),
        progresiva: (map['progresiva'] ?? '') as String,
        seccion: map['seccion'] as String?,
        estructura: map['estructura'] as String?,
        ohm1m: (map['ohm1m'] as num?)?.toDouble(),
        ohm3m: (map['ohm3m'] as num?)?.toDouble(),
        latitude: (map['latitude'] as num?)?.toDouble(),
        longitude: (map['longitude'] as num?)?.toDouble(),
        observations: (map['observations'] ?? '') as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['createdAt'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch,
        ),
      );

  Map<String, Object?> toJson() => toMap();
  factory Measurement.fromJson(Map<String, Object?> json) =>
      Measurement.fromMap(json);

  @override
  String toString() =>
      'Measurement(id: $id, sheetId: $sheetId, prog: $progresiva, '
      'ohm1m: $ohm1m, ohm3m: $ohm3m, lat: $latitude, lng: $longitude, obs: $observations)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Measurement &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          sheetId == other.sheetId &&
          progresiva == other.progresiva &&
          seccion == other.seccion &&
          estructura == other.estructura &&
          ohm1m == other.ohm1m &&
          ohm3m == other.ohm3m &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          observations == other.observations &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        sheetId,
        progresiva,
        seccion,
        estructura,
        ohm1m,
        ohm3m,
        latitude,
        longitude,
        observations,
        createdAt,
      );
}
