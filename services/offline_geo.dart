// lib/services/offline_geo.dart
import 'dart:async';
import 'package:geolocator/geolocator.dart';

class OfflineGeo {
  /// Llama esto al inicio para asegurar permisos/servicio.
  static Future<bool> ensureReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  /// Coordenadas offline con buena UX:
  /// 1) devuelve rÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¡pido el lastKnown si existe
  /// 2) intenta un fix de GPS con alta precisiÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³n y timeout
  static Future<Position?> current({
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final last = await Geolocator.getLastKnownPosition();
    try {
      final pos = await Geolocator.getCurrentPosition(
        // En geolocator 10.x esto sigue vÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¡lido:
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(timeout);
      return pos;
    } on TimeoutException {
      return last;
    } catch (_) {
      return last;
    }
  }

  /// Stream para ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã¢â‚¬Å“calentarÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â y recibir updates (offline)
  static Stream<Position> watch({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilterMeters = 5,
  }) {
    // En geolocator 10.x+ usar LocationSettings
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilterMeters,
      ),
    );
  }
}
