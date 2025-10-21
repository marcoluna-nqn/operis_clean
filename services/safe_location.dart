// lib/services/safe_location.dart
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class SafeLocation {
  SafeLocation._();
  static final SafeLocation instance = SafeLocation._();

  // ~0 en decimales, para evitar (0,0)
  static const double _kZero = 1e-6;
  static const Duration _kTimeout = Duration(seconds: 12);
  static const Duration _kMaxAge = Duration(minutes: 15);

  /// Valida el rango y que no sea (0,0)
  bool isValidPosition(Position p) {
    final la = p.latitude, lo = p.longitude;
    final notZero = la.abs() > _kZero || lo.abs() > _kZero;
    return la.isFinite &&
        lo.isFinite &&
        la >= -90 &&
        la <= 90 &&
        lo >= -180 &&
        lo <= 180 &&
        notZero;
  }

  bool isValidLatLng(double? la, double? lo) {
    if (la == null || lo == null) return false;
    return la >= -90 &&
        la <= 90 &&
        lo >= -180 &&
        lo <= 180 &&
        (la.abs() > _kZero || lo.abs() > _kZero);
  }

  Future<bool> _ensureServiceAndPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

  /// Devuelve una posiciÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³n **segura**:
  /// 1) actual con alta precisiÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³n y timeout
  /// 2) si falla, ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Âºltima conocida, vÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¡lida y reciente
  Future<Position?> getSafePosition() async {
    final ok = await _ensureServiceAndPermission();
    if (!ok) return null;

    // 1) Actual
    try {
      final now = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: _kTimeout,
      );
      if (isValidPosition(now)) return now;
    } catch (_) {}

    // 2) ÃƒÆ’Ã†â€™Ãƒâ€¦Ã‚Â¡ltima conocida (si es vÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¡lida y reciente)
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null &&
          isValidPosition(last) &&
          DateTime.now().difference(
                  last.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0)) <=
              _kMaxAge) {
        return last;
      }
    } catch (_) {}

    return null;
  }

  /// Redondea a 6 decimales para compartir/guardar
  Map<String, double> round6(double la, double lo) => {
        'lat': double.parse(la.toStringAsFixed(6)),
        'lng': double.parse(lo.toStringAsFixed(6)),
      };

  /// Abre Google Maps / app de mapas si las coords son vÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¡lidas
  Future<bool> openInMaps(double lat, double lng) async {
    if (!isValidLatLng(lat, lng)) return false;
    final uri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    // Fallback a web
    final web = Uri.parse('https://maps.google.com/?q=$lat,$lng');
    return launchUrl(web, mode: LaunchMode.externalApplication);
  }
}
