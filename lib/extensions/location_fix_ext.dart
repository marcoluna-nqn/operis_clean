// lib/extensions/location_fix_ext.dart
// Extensiones utilitarias sobre LocationFix: formato, distancias, rumbos, links.
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart' show Geolocator;
import '../services/location_service.dart';

extension LocationFixX on LocationFix {
  // Texto corto
  String get latText => latitude.toStringAsFixed(6);
  String get lngText => longitude.toStringAsFixed(6);
  String get latLngText => '$latText, $lngText';
  String get accuracyText =>
      accuracyMeters != null ? '±${accuracyMeters!.toStringAsFixed(0)}m' : '';

  /// Señal rápida de precisión: 🟢 <=10m, 🟡 <=25m, 🟠 <=60m, 🔴 >60m, 📍 sin dato
  String get accuracyEmoji {
    final m = accuracyMeters;
    if (m == null) return '📍';
    if (m <= 10) return '🟢';
    if (m <= 25) return '🟡';
    if (m <= 60) return '🟠';
    return '🔴';
  }

  /// URL web a Google Maps.
  Uri get mapsUri => Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latText,$lngText');

  /// URI geo:nativo (Android). `label` opcional.
  Uri geoUri({String? label}) {
    final labelPart = (label == null || label.trim().isEmpty)
        ? ''
        : '(${Uri.encodeComponent(label)})';
    return Uri.parse('geo:$latText,$lngText$labelPart');
  }

  /// Texto listo para compartir.
  String toShareText({String? label}) =>
      'Ubicación: $latText, $lngText\n${geoUri(label: label)}\n$mapsUri';

  /// Distancia a otra ubicación (metros).
  double distanceTo(LocationFix other) => Geolocator.distanceBetween(
    latitude,
    longitude,
    other.latitude,
    other.longitude,
  );

  /// Distancia a lat/lng (metros).
  double distanceToLatLng(double lat, double lng) =>
      Geolocator.distanceBetween(latitude, longitude, lat, lng);

  /// Rumbo geodésico (0..360°) hacia lat/lng. Null si inválido.
  double? bearingToLatLng(double lat, double lng) {
    if (!_ok(lat, lng)) return null;
    final lat1 = _rad(latitude), lat2 = _rad(lat);
    final dLon = _rad(lng - longitude);
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final brng = (math.atan2(y, x) * 180 / math.pi + 360) % 360;
    return brng;
  }

  /// Mueve el fix unos metros en un rumbo dado. Útil para separar puntos superpuestos.
  LocationFix nudged({double meters = 1, double bearingDeg = 0}) {
    final (nlat, nlng) = _offsetMeters(latitude, longitude, meters, bearingDeg);
    return copyWith(
      latitude: nlat,
      longitude: nlng,
      accuracyMeters: (accuracyMeters ?? 10) + meters * 0.1,
    );
  }

  /// JSON “humano” amigable para logs/export.
  Map<String, dynamic> toPrettyJson() => {
    'lat': latText,
    'lng': lngText,
    'accuracy': accuracyText,
    'ts': timestamp.toIso8601String(),
    'used': usedSamples,
    'discarded': discardedSamples,
  };
}

// ---- helpers locales ----
bool _ok(double lat, double lng) =>
    lat.isFinite && lng.isFinite && lat.abs() <= 90 && lng.abs() <= 180;

double _rad(double d) => d * math.pi / 180.0;

(double, double) _offsetMeters(
    double lat, double lng, double meters, double bearingDeg) {
  const R = 6371000.0;
  final br = bearingDeg * math.pi / 180.0;
  final dr = meters / R;
  final lat1 = _rad(lat);
  final lng1 = _rad(lng);

  final sinLat2 =
      math.sin(lat1) * math.cos(dr) + math.cos(lat1) * math.sin(dr) * math.cos(br);
  final lat2 = math.asin(sinLat2);
  final y = math.sin(br) * math.sin(dr) * math.cos(lat1);
  final x = math.cos(dr) - math.sin(lat1) * math.sin(lat2);
  final lng2 = lng1 + math.atan2(y, x);

  return (lat2 * 180.0 / math.pi, lng2 * 180.0 / math.pi);
}
