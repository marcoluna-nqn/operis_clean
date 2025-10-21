// lib/utils/geo_utils.dart
import 'dart:math';

class GeoUtils {
  /// Devuelve `true` si (lat, lng) están dentro de rangos válidos y no es (0,0).
  static bool isValid(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat.isNaN || lng.isNaN) return false;
    if (lat < -90 || lat > 90) return false;
    if (lng < -180 || lng > 180) return false;
    if (_isZero(lat, lng)) return false;
    return true;
  }

  /// Distancia aproximada en metros usando Haversine.
  static double distanceMeters({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    const r = 6371000.0; // radio Tierra en metros
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            (sin(dLng / 2) * sin(dLng / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  static bool _isZero(double lat, double lng) {
    // tolerancia por si vienen números muy pequeños en lugar de 0 exacto
    const eps = 1e-9;
    return lat.abs() < eps && lng.abs() < eps;
  }

  static double _deg2rad(double d) => d * (pi / 180.0);
}
