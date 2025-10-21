// lib/services/ultra_precise_engine.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';

/// Fix minimalista para no depender de otras clases.
class UltraFix {
  final double lat;
  final double lng;
  final double accuracyM;
  final double? altM;
  final double? speedMps;
  final double? headingDeg;
  final DateTime ts;
  const UltraFix({
    required this.lat,
    required this.lng,
    required this.accuracyM,
    this.altM,
    this.speedMps,
    this.headingDeg,
    required this.ts,
  });
}

/// Motor de captura robusta sin internet.
/// - Muestra N posiciones con alta precisiÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³n.
/// - Filtra outliers con MAD (desviaciÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³n absoluta mediana).
/// - Hace promedio ponderado por 1/accuracy^2.
/// - Fallback a lastKnown / one-shot con timeout.
class UltraPreciseEngine {
  UltraPreciseEngine._();
  static final UltraPreciseEngine instance = UltraPreciseEngine._();

  Future<UltraFix> capture({
    Duration warmup = const Duration(seconds: 2),
    Duration window = const Duration(seconds: 10),
    int maxSamples = 40,
    double targetAccM = 25.0,
  }) async {
    // Pre-chequeos mÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â­nimos (dejÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¡ permisos/servicio al caller)
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw 'Servicio de ubicaciÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³n desactivado';
    }

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );

    final List<Position> bucket = [];
    final sub =
        Geolocator.getPositionStream(locationSettings: settings).listen((p) {
      if (p.isMocked == true) return;
      if (p.latitude == 0 && p.longitude == 0) return;
      if (!p.latitude.isFinite || !p.longitude.isFinite) return;
      bucket.add(p);
      if (bucket.length > maxSamples) bucket.removeAt(0);
    });

    // Warmup + ventana de muestreo
    await Future<void>.delayed(warmup);
    final sw = Stopwatch()..start();
    while (sw.elapsed < window && bucket.length < maxSamples) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (_bestAccuracy(bucket) <= targetAccM) break;
    }
    await sub.cancel();

    // Fallbacks si no hay lecturas buenas
    if (bucket.isEmpty) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return UltraFix(
          lat: last.latitude,
          lng: last.longitude,
          accuracyM: last.accuracy,
          altM: last.altitude.isFinite ? last.altitude : null,
          speedMps: last.speed.isFinite ? last.speed : null,
          headingDeg: last.heading.isFinite ? last.heading : null,
          ts: last.timestamp ?? DateTime.now().toUtc(),
        );
      }
      final one = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 6),
      );
      return UltraFix(
        lat: one.latitude,
        lng: one.longitude,
        accuracyM: one.accuracy,
        altM: one.altitude.isFinite ? one.altitude : null,
        speedMps: one.speed.isFinite ? one.speed : null,
        headingDeg: one.heading.isFinite ? one.heading : null,
        ts: one.timestamp ?? DateTime.now().toUtc(),
      );
    }

    // Filtrado robusto (MAD en metros sobre la mediana)
    final med = _medianLatLng(bucket);
    final dists = bucket
        .map((p) =>
            Geolocator.distanceBetween(med.$1, med.$2, p.latitude, p.longitude))
        .toList()
      ..sort();
    final medianDist = dists[dists.length ~/ 2];
    final mad = _medianAbsDeviation(dists);
    final thr = medianDist + 2.8 * mad; // umbral robusto

    final kept = <Position>[];
    for (var i = 0; i < bucket.length; i++) {
      if (dists[i] <= thr) kept.add(bucket[i]);
    }
    if (kept.isEmpty) kept.addAll(bucket);

    // Promedio ponderado por 1/accuracy^2
    double wsum = 0, lat = 0, lng = 0;
    for (final p in kept) {
      final acc = math.max(3.0, p.accuracy); // evita pesos extremos
      final w = 1.0 / (acc * acc);
      wsum += w;
      lat += p.latitude * w;
      lng += p.longitude * w;
    }
    lat /= wsum;
    lng /= wsum;

    // PrecisiÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³n combinada: peor entre mejor accuracy reportada y MAD escalado
    final bestReported = kept.map((e) => e.accuracy).reduce(math.min);
    final estAcc = mad *
        1.4826; // aproximaciÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³n robusta ~ÃƒÆ’Ã‚ÂÃƒâ€ Ã¢â‚¬â„¢
    final acc = math.max(bestReported, estAcc);

    final ref = kept.first;
    return UltraFix(
      lat: lat,
      lng: lng,
      accuracyM: acc.isFinite ? acc : bestReported,
      altM: ref.altitude.isFinite ? ref.altitude : null,
      speedMps: ref.speed.isFinite ? ref.speed : null,
      headingDeg: ref.heading.isFinite ? ref.heading : null,
      ts: ref.timestamp ?? DateTime.now().toUtc(),
    );
  }

  static double _bestAccuracy(List<Position> xs) =>
      xs.isEmpty ? double.infinity : xs.map((e) => e.accuracy).reduce(math.min);

  static (double, double) _medianLatLng(List<Position> xs) {
    final lats = xs.map((e) => e.latitude).toList()..sort();
    final lngs = xs.map((e) => e.longitude).toList()..sort();
    double med(List<double> v) => v.length.isOdd
        ? v[v.length ~/ 2]
        : (v[v.length ~/ 2 - 1] + v[v.length ~/ 2]) / 2.0;
    return (med(lats), med(lngs));
  }

  static double _medianAbsDeviation(List<double> v) {
    if (v.isEmpty) return 0;
    final sorted = [...v]..sort();
    final m = sorted[sorted.length ~/ 2];
    final devs = v.map((x) => (x - m).abs()).toList()..sort();
    return devs[devs.length ~/ 2];
  }
}
