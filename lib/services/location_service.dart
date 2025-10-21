// lib/services/location_service.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, debugPrint, debugPrintStack;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

typedef CancelToken = ValueListenable<bool>;

class LocationException implements Exception {
  final String message;
  const LocationException(this.message);
  @override
  String toString() => 'LocationException: $message';
}

/// Fix con metadatos útiles para planillas/export.
class LocationFix {
  final double latitude;
  final double longitude;
  final double? accuracyMeters; // ~68%
  final double? altitudeMeters;
  final double? speedMps;
  final double? headingDeg;
  final DateTime timestamp;
  final int usedSamples;
  final int discardedSamples;

  const LocationFix({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.altitudeMeters,
    this.speedMps,
    this.headingDeg,
    required this.timestamp,
    this.usedSamples = 1,
    this.discardedSamples = 0,
  });

  factory LocationFix.fromPosition(Position p, {int used = 1, int discarded = 0}) {
    return LocationFix(
      latitude: p.latitude,
      longitude: p.longitude,
      accuracyMeters: _finiteOrNull(p.accuracy),
      altitudeMeters: _finiteOrNull(p.altitude),
      speedMps: _finiteOrNull(p.speed),
      headingDeg: _finiteOrNull(p.heading),
      // p.timestamp es DateTime? en geolocator → fallback seguro.
      timestamp: p.timestamp ?? DateTime.now(),
      usedSamples: used,
      discardedSamples: discarded,
    );
  }

  LocationFix copyWith({
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    double? altitudeMeters,
    double? speedMps,
    double? headingDeg,
    DateTime? timestamp,
    int? usedSamples,
    int? discardedSamples,
  }) {
    return LocationFix(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      altitudeMeters: altitudeMeters ?? this.altitudeMeters,
      speedMps: speedMps ?? this.speedMps,
      headingDeg: headingDeg ?? this.headingDeg,
      timestamp: timestamp ?? this.timestamp,
      usedSamples: usedSamples ?? this.usedSamples,
      discardedSamples: discardedSamples ?? this.discardedSamples,
    );
  }

  String toGeoUri({String? label}) => _geoUri(latitude, longitude, label: label).toString();
  Uri toMapsUri() => _mapsUri(latitude, longitude);

  LocationFix rounded({int decimals = 6}) {
    double r(double v) => double.parse(v.toStringAsFixed(decimals));
    return copyWith(latitude: r(latitude), longitude: r(longitude));
  }

  String fingerprint({int latLngDecimals = 5, Duration bucket = const Duration(minutes: 2)}) {
    final dtBucket = DateTime.utc(
      timestamp.year,
      timestamp.month,
      timestamp.day,
      timestamp.hour,
      timestamp.minute - (timestamp.minute % math.max(1, bucket.inMinutes)),
    );
    final latR = double.parse(latitude.toStringAsFixed(latLngDecimals));
    final lngR = double.parse(longitude.toStringAsFixed(latLngDecimals));
    return '${latR}_${lngR}_${dtBucket.toIso8601String()}';
  }

  Map<String, dynamic> toJson() => {
    'lat': latitude,
    'lng': longitude,
    'accuracy': accuracyMeters,
    'alt': altitudeMeters,
    'speed': speedMps,
    'heading': headingDeg,
    'ts': timestamp.toUtc().toIso8601String(),
    'samples_used': usedSamples,
    'samples_discarded': discardedSamples,
  };

  static double? _finiteOrNull(double v) => (v.isNaN || v.isInfinite) ? null : v;
}

class AdaptiveFixConfig {
  final Duration freshAge;
  final double acceptAccuracyMeters;
  final Duration fastTryTimeout;
  final Duration windowForBetter;
  final int preciseSamples;
  final double keepBestFraction;

  const AdaptiveFixConfig({
    this.freshAge = const Duration(seconds: 30),
    this.acceptAccuracyMeters = 25.0,
    this.fastTryTimeout = const Duration(seconds: 2),
    this.windowForBetter = const Duration(seconds: 5),
    this.preciseSamples = 6,
    this.keepBestFraction = 0.5,
  });
}

/// Abstracción para testeabilidad (inyectable / mockeable).
abstract class GeoPlatform {
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<LocationAccuracyStatus> getLocationAccuracy();
  Future<LocationAccuracyStatus> requestTemporaryFullAccuracy({required String purposeKey});
  Future<Position> getCurrentPosition({required LocationSettings settings});
  Stream<Position> getPositionStream({required LocationSettings settings});
  Future<Position?> getLastKnownPosition();
  Future<bool> openLocationSettings();
  Future<bool> openAppSettings();
}

/// Implementación por defecto con geolocator.
class _GeoPlatformGeolocator implements GeoPlatform {
  @override
  Future<bool> isLocationServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() => Geolocator.requestPermission();

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() => Geolocator.getLocationAccuracy();

  @override
  Future<LocationAccuracyStatus> requestTemporaryFullAccuracy({required String purposeKey}) =>
      Geolocator.requestTemporaryFullAccuracy(purposeKey: purposeKey);

  @override
  Future<Position> getCurrentPosition({required LocationSettings settings}) =>
      Geolocator.getCurrentPosition(locationSettings: settings);

  @override
  Stream<Position> getPositionStream({required LocationSettings settings}) =>
      Geolocator.getPositionStream(locationSettings: settings);

  @override
  Future<Position?> getLastKnownPosition() => Geolocator.getLastKnownPosition();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
}

/// Reloj inyectable para test.
abstract class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  @override
  DateTime now() => DateTime.now();
}

/// Suavizador ponderado por precisión (IVW acumulativo).
class _PrecisionSmoother {
  LocationFix? _last;
  double? _lastWeight; // 1/sigma^2 acumulado

  LocationFix add(LocationFix fix) {
    double sigma(double? a) => (a == null || !a.isFinite || a <= 0) ? 50.0 : a;

    if (_last == null) {
      final s = sigma(fix.accuracyMeters);
      _last = fix;
      _lastWeight = 1.0 / (s * s);
      return fix;
    }

    final sNew = sigma(fix.accuracyMeters);
    final wPrev = _lastWeight ?? 0.0;
    final wNew = 1.0 / (sNew * sNew);
    final wTot = wPrev + wNew;
    if (wTot <= 0) return fix;

    final lat = ((_last!.latitude * wPrev) + (fix.latitude * wNew)) / wTot;
    final lng = ((_last!.longitude * wPrev) + (fix.longitude * wNew)) / wTot;

    final fusedAcc = 1.0 / math.sqrt(wTot);

    final fused = fix.copyWith(
      latitude: lat,
      longitude: lng,
      accuracyMeters: LocationFix._finiteOrNull(fusedAcc),
      usedSamples: fix.usedSamples + _last!.usedSamples,
      discardedSamples: fix.discardedSamples + _last!.discardedSamples,
    );

    _last = fused;
    _lastWeight = wTot;
    return fused;
  }
}

class LocationService {
  LocationService._(this._geo, this._clock);
  static final LocationService instance =
  LocationService._(_GeoPlatformGeolocator(), SystemClock());

  // Permite inyectar dobles/mocks en tests.
  void configure({GeoPlatform? geo, Clock? clock}) {
    if (geo != null) _geo = geo;
    if (clock != null) _clock = clock;
  }

  GeoPlatform _geo;
  Clock _clock;

  static const Duration _getCurrentTimeout = Duration(seconds: 10);
  static const Duration _lastKnownMaxAge = Duration(minutes: 2);
  static const Duration _lastKnownMaxAgeOnTimeout = Duration(hours: 24);
  static const double _maxAcceptableAccuracyMeters = 150.0;

  final ValueNotifier<LocationFix?> _cache = ValueNotifier<LocationFix?>(null);
  ValueListenable<LocationFix?> get lastFixListenable => _cache;

  // ---------- permisos ----------
  Future<void> _ensureServiceAndPermission() async {
    if (!await _geo.isLocationServiceEnabled()) {
      throw const LocationException('Activá el servicio de ubicación del dispositivo.');
    }
    var perm = await _geo.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await _geo.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      throw const LocationException('El permiso de ubicación fue denegado.');
    }
    if (perm == LocationPermission.deniedForever) {
      throw const LocationException('Permiso denegado permanentemente. Habilitalo en Ajustes.');
    }
  }

  Future<bool> hasPermission() async {
    final perm = await _geo.checkPermission();
    return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
  }

  Future<bool> ensureFullAccuracy({String? iosPurposeKey}) async {
    final status = await _geo.getLocationAccuracy();
    if (status == LocationAccuracyStatus.precise) return true;
    if (Platform.isIOS) {
      try {
        final result = await _geo.requestTemporaryFullAccuracy(
          purposeKey: iosPurposeKey ?? 'FullAccuracyUsage',
        );
        return result == LocationAccuracyStatus.precise;
      } catch (_) {}
    }
    return false;
  }

  Future<bool> openSystemLocationSettings() => _geo.openLocationSettings();
  Future<bool> openAppSettings() => _geo.openAppSettings();

  // ---------- lecturas base ----------
  Future<Position> currentPosition({
    LocationAccuracy accuracy = LocationAccuracy.best,
    Duration? timeout,
    bool tryFullAccuracyIOS = false,
    String? iosPurposeKey,
  }) async {
    await _ensureServiceAndPermission();
    if (tryFullAccuracyIOS && Platform.isIOS) {
      await ensureFullAccuracy(iosPurposeKey: iosPurposeKey);
    }
    final settings = LocationSettings(accuracy: accuracy, timeLimit: timeout);
    return _geo.getCurrentPosition(settings: settings);
  }

  Future<LocationFix> getCurrentFix({
    LocationAccuracy? desiredAccuracy,
    Duration timeout = _getCurrentTimeout,
    bool rejectMocked = true,
    bool tryFullAccuracyIOS = false,
    String? iosPurposeKey,
  }) async {
    final p = await getCurrent(
      desiredAccuracy: desiredAccuracy,
      timeout: timeout,
      rejectMocked: rejectMocked,
      tryFullAccuracyIOS: tryFullAccuracyIOS,
      iosPurposeKey: iosPurposeKey,
    );
    final fix = LocationFix.fromPosition(p);
    _cache.value = fix;
    return fix;
  }

  Future<Position> getCurrent({
    LocationAccuracy? desiredAccuracy,
    Duration timeout = _getCurrentTimeout,
    bool rejectMocked = true,
    bool tryFullAccuracyIOS = false,
    String? iosPurposeKey,
  }) async {
    await _ensureServiceAndPermission();
    if (tryFullAccuracyIOS && Platform.isIOS) {
      await ensureFullAccuracy(iosPurposeKey: iosPurposeKey);
    }
    final acc =
        desiredAccuracy ?? (Platform.isIOS ? LocationAccuracy.bestForNavigation : LocationAccuracy.best);

    try {
      final p = await _geo.getCurrentPosition(
        settings: LocationSettings(accuracy: acc, timeLimit: timeout),
      );
      if (!_validPos(p, rejectMocked: rejectMocked)) {
        throw const LocationException('Fix inválido (0,0 o precisión no válida).');
      }
      return p;
    } on TimeoutException {
      // OFFLINE: aceptar last-known más viejo si hubo timeout
      final last = await _geo.getLastKnownPosition();
      if (last != null && _validPos(last, rejectMocked: rejectMocked)) {
        final age = _clock.now().difference(last.timestamp ?? _clock.now());
        if (age <= _lastKnownMaxAgeOnTimeout) {
          return last;
        }
      }
      throw const LocationException('Tiempo agotado. No se obtuvo una ubicación reciente.');
    } catch (e, st) {
      _logError(e, st);
      throw LocationException('No se pudo obtener la ubicación: $e');
    }
  }

  Future<Position?> getLastKnown() => _geo.getLastKnownPosition();

  // ---------- lecturas precisas por muestras ----------
  Future<LocationFix> getPreciseFix({
    int samples = 8,
    Duration perSampleTimeout = const Duration(seconds: 4),
    double keepBestFraction = 0.5,
    bool rejectMocked = true,
    double minUniqueMeters = 0.5,
    LocationAccuracy? desiredAccuracy,
    bool tryFullAccuracyIOS = false,
    String? iosPurposeKey,
    CancelToken? cancelToken,
  }) async {
    assert(samples > 0 && keepBestFraction > 0 && keepBestFraction <= 1);
    await _ensureServiceAndPermission();
    _throwIfCancelled(cancelToken);

    if (tryFullAccuracyIOS && Platform.isIOS) {
      await ensureFullAccuracy(iosPurposeKey: iosPurposeKey);
    }

    final desired =
        desiredAccuracy ?? (Platform.isIOS ? LocationAccuracy.bestForNavigation : LocationAccuracy.best);

    final List<Position> bucket = <Position>[];
    int discarded = 0;
    Position? lastAccepted;

    for (var i = 0; i < samples; i++) {
      _throwIfCancelled(cancelToken);
      try {
        final p = await _geo.getCurrentPosition(
          settings: LocationSettings(accuracy: desired, timeLimit: perSampleTimeout),
        );

        if (_validPos(p, rejectMocked: rejectMocked)) {
          final la = lastAccepted;
          if (la == null ||
              Geolocator.distanceBetween(la.latitude, la.longitude, p.latitude, p.longitude) >=
                  minUniqueMeters) {
            bucket.add(p);
            lastAccepted = p;
          } else {
            discarded++;
          }
        } else {
          discarded++;
        }
      } on TimeoutException {
        discarded++;
      } catch (_) {
        discarded++;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    if (bucket.isEmpty) {
      throw const LocationException('No se obtuvieron lecturas de GPS válidas.');
    }

    final fix = _processLocationBucketWeighted(
      bucket: bucket,
      discardedCount: discarded,
      keepBestFraction: keepBestFraction,
    );
    _cache.value = fix;
    return fix;
  }

  // ---------- AdaptiveFix: rápido y luego mejor ----------
  Future<LocationFix> getAdaptiveFix({
    AdaptiveFixConfig config = const AdaptiveFixConfig(),
    bool tryFullAccuracyIOS = false,
    String? iosPurposeKey,
    CancelToken? cancelToken,
    void Function(LocationFix better)? onBetterFix,
  }) async {
    await _ensureServiceAndPermission();
    _throwIfCancelled(cancelToken);

    // 1) last-known si es fresco y preciso.
    final last = await _geo.getLastKnownPosition();
    if (last != null &&
        _clock.now().difference(last.timestamp ?? _clock.now()) <= config.freshAge &&
        _validPos(last, rejectMocked: true) &&
        last.accuracy <= config.acceptAccuracyMeters) {
      final quick = LocationFix.fromPosition(last);
      _cache.value = quick;
      unawaited(_seekBetterWithinWindow(
        base: quick,
        config: config,
        tryFullAccuracyIOS: tryFullAccuracyIOS,
        iosPurposeKey: iosPurposeKey,
        onBetterFix: onBetterFix,
      ));
      return quick;
    }

    // 2) Fallback: intento rápido -> mejora dentro de ventana -> preciso.
    try {
      final first = await _fastTry(config, tryFullAccuracyIOS, iosPurposeKey);
      _cache.value = first;
      if ((first.accuracyMeters ?? 9999) > config.acceptAccuracyMeters) {
        unawaited(_seekBetterWithinWindow(
          base: first,
          config: config,
          tryFullAccuracyIOS: tryFullAccuracyIOS,
          iosPurposeKey: iosPurposeKey,
          onBetterFix: onBetterFix,
        ));
      }
      return first;
    } catch (_) {
      final precise = await _preciseWindow(config, tryFullAccuracyIOS, iosPurposeKey);
      _cache.value = precise;
      return precise;
    }
  }

  Future<LocationFix> _fastTry(
      AdaptiveFixConfig config,
      bool tryFullAccuracyIOS,
      String? iosPurposeKey,
      ) async {
    try {
      final p = await getCurrent(
        desiredAccuracy: LocationAccuracy.high,
        timeout: config.fastTryTimeout,
        rejectMocked: true,
        tryFullAccuracyIOS: tryFullAccuracyIOS,
        iosPurposeKey: iosPurposeKey,
      );
      return LocationFix.fromPosition(p);
    } on Exception {
      // OFFLINE: si falla el quick fix, aceptar last-known hasta 24h
      final last = await _geo.getLastKnownPosition();
      if (last != null &&
          _clock.now().difference(last.timestamp ?? _clock.now()) <= _lastKnownMaxAgeOnTimeout &&
          _isValid(last.latitude, last.longitude)) {
        return LocationFix.fromPosition(last);
      }
      rethrow;
    }
  }

  Future<LocationFix> _preciseWindow(
      AdaptiveFixConfig config,
      bool tryFullAccuracyIOS,
      String? iosPurposeKey,
      ) {
    return getPreciseFix(
      samples: config.preciseSamples,
      perSampleTimeout: Duration(
        milliseconds: math.max(600, (config.windowForBetter.inMilliseconds ~/ config.preciseSamples)),
      ),
      keepBestFraction: config.keepBestFraction,
      rejectMocked: true,
      tryFullAccuracyIOS: tryFullAccuracyIOS,
      iosPurposeKey: iosPurposeKey,
    );
  }

  Future<void> _seekBetterWithinWindow({
    required LocationFix base,
    required AdaptiveFixConfig config,
    required bool tryFullAccuracyIOS,
    required String? iosPurposeKey,
    void Function(LocationFix better)? onBetterFix,
  }) async {
    final endAt = _clock.now().add(config.windowForBetter);
    LocationFix best = base;
    while (_clock.now().isBefore(endAt)) {
      try {
        final candidate = await getPreciseFix(
          samples: 3,
          perSampleTimeout: const Duration(seconds: 2),
          keepBestFraction: 0.67,
          rejectMocked: true,
          tryFullAccuracyIOS: tryFullAccuracyIOS,
          iosPurposeKey: iosPurposeKey,
        );
        if ((candidate.accuracyMeters ?? 9999) < (best.accuracyMeters ?? 9999)) {
          best = candidate;
          _cache.value = best;
          if (onBetterFix != null) onBetterFix(best);
          if ((best.accuracyMeters ?? 9999) <= config.acceptAccuracyMeters) break;
        }
      } catch (_) {}
    }
  }

  // ---------- stream con jump-filter ----------
  Stream<LocationFix> watchFixes({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilterMeters = 2,
    double rejectAboveAccuracyMeters = 100,
    Duration staleAfter = const Duration(seconds: 15),
    bool deadReckoningOnDrop = true,
    double maxSpeedMps = 70.0, // ~252 km/h
    double jumpGuardMetersBuffer = 20.0,
  }) async* {
    await _ensureServiceAndPermission();

    final smoother = _PrecisionSmoother();
    Position? lastPos;
    DateTime? lastEmitTime;
    LocationFix? lastFix;

    final stream = _geo.getPositionStream(
      settings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilterMeters,
      ),
    );

    await for (final p in stream) {
      if (!_validPos(p, rejectMocked: true)) continue;
      if (p.accuracy > rejectAboveAccuracyMeters) continue;

      final now = _clock.now();
      if (lastFix != null && lastPos != null) {
        final dt =
            (p.timestamp ?? now).difference(lastPos.timestamp ?? now).inMilliseconds / 1000.0;
        final dtSafe = dt > 0 ? dt : 1.0;
        final dist = Geolocator.distanceBetween(
          lastFix.latitude,
          lastFix.longitude,
          p.latitude,
          p.longitude,
        );
        if (dist > (maxSpeedMps * dtSafe + jumpGuardMetersBuffer)) {
          // salto irreal → descartar
          continue;
        }
      }

      final fix = LocationFix.fromPosition(p);
      final fused = smoother.add(fix);
      lastPos = p;
      lastFix = fused;
      lastEmitTime = now;
      _cache.value = fused;
      yield fused;
    }

    if (deadReckoningOnDrop && lastPos != null && lastFix != null && lastEmitTime != null) {
      final until = lastEmitTime.add(staleAfter);
      while (_clock.now().isBefore(until)) {
        final ex = _extrapolate(lastFix, after: const Duration(seconds: 1));
        _cache.value = ex;
        yield ex;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  // ---------- utilidades UI ----------
  Future<bool> openInMaps({required double lat, required double lng, String? label}) async {
    if (!_isValid(lat, lng)) return false;
    final geo = _geoUri(lat, lng, label: label);
    if (await canLaunchUrl(geo)) {
      return launchUrl(geo, mode: LaunchMode.externalApplication);
    }
    final web = _mapsUri(lat, lng);
    return launchUrl(web, mode: LaunchMode.externalApplication);
  }

  String mapsUrl(double lat, double lng) => _mapsUri(lat, lng).toString();

  String shareTextFor(double lat, double lng, {String? label}) {
    final ok = _isValid(lat, lng);
    final fLat = ok ? _fmt(lat) : '-';
    final fLng = ok ? _fmt(lng) : '-';
    final geo = ok ? _geoUri(lat, lng, label: label).toString() : '';
    final web = ok ? _mapsUri(lat, lng).toString() : '';
    return 'Ubicación: $fLat, $fLng\n$geo\n$web';
  }

  // ---------- helpers ----------
  bool _validPos(Position p, {bool rejectMocked = true}) {
    if (!_isValid(p.latitude, p.longitude)) return false;
    if (!p.accuracy.isFinite || p.accuracy <= 0 || p.accuracy > _maxAcceptableAccuracyMeters) {
      return false;
    }
    if (rejectMocked && p.isMocked == true) return false;
    return true;
  }

  void _throwIfCancelled(CancelToken? t) {
    if (t?.value == true) {
      throw const LocationException('Operación cancelada por el usuario.');
    }
  }

  LocationFix _processLocationBucketWeighted({
    required List<Position> bucket,
    required int discardedCount,
    required double keepBestFraction,
  }) {
    bucket.sort((a, b) => a.accuracy.compareTo(b.accuracy));
    final int keepNum = (bucket.length * keepBestFraction).clamp(1, bucket.length).toInt();
    final List<Position> kept = bucket.take(keepNum).toList();

    double totalWeight = 0;
    double weightedLat = 0;
    double weightedLng = 0;

    for (final p in kept) {
      final double weight = 1.0 / ((p.accuracy * p.accuracy) + 1e-9); // 1/var
      totalWeight += weight;
      weightedLat += p.latitude * weight;
      weightedLng += p.longitude * weight;
    }

    if (totalWeight == 0) {
      return _processLocationBucket(
        bucket: bucket,
        discardedCount: discardedCount,
        keepBestFraction: keepBestFraction,
      );
    }

    final double avgLat = weightedLat / totalWeight;
    final double avgLng = weightedLng / totalWeight;
    if (!_isValid(avgLat, avgLng)) {
      throw const LocationException('Fix inválido después de procesar (0,0).');
    }

    final Position ref = kept.first;
    final double bestReported = kept.first.accuracy;

    return LocationFix(
      latitude: avgLat,
      longitude: avgLng,
      accuracyMeters: LocationFix._finiteOrNull(bestReported),
      altitudeMeters: LocationFix._finiteOrNull(ref.altitude),
      speedMps: LocationFix._finiteOrNull(ref.speed),
      headingDeg: LocationFix._finiteOrNull(ref.heading),
      timestamp: (ref.timestamp ?? _clock.now()),
      usedSamples: kept.length,
      discardedSamples: discardedCount + (bucket.length - kept.length),
    );
  }

  LocationFix _processLocationBucket({
    required List<Position> bucket,
    required int discardedCount,
    required double keepBestFraction,
  }) {
    bucket.sort((a, b) => a.accuracy.compareTo(b.accuracy));
    final int keepNum = (bucket.length * keepBestFraction).clamp(1, bucket.length).toInt();
    final List<Position> kept = bucket.take(keepNum).toList();

    final double avgLat =
        kept.map((p) => p.latitude).reduce((a, b) => a + b) / kept.length;
    final double avgLng =
        kept.map((p) => p.longitude).reduce((a, b) => a + b) / kept.length;

    if (!_isValid(avgLat, avgLng)) {
      throw const LocationException('Fix inválido (0,0).');
    }

    final List<double> dists = kept
        .map((p) => Geolocator.distanceBetween(avgLat, avgLng, p.latitude, p.longitude))
        .toList()
      ..sort();
    final double medianDist = dists[dists.length ~/ 2];
    final double estAccuracy = medianDist * 1.4826; // MAD -> sigma aprox
    final double bestReported = kept.first.accuracy;
    final double accuracy = estAccuracy > bestReported ? estAccuracy : bestReported;

    final Position ref = kept.first;
    return LocationFix(
      latitude: avgLat,
      longitude: avgLng,
      accuracyMeters: LocationFix._finiteOrNull(accuracy),
      altitudeMeters: LocationFix._finiteOrNull(ref.altitude),
      speedMps: LocationFix._finiteOrNull(ref.speed),
      headingDeg: LocationFix._finiteOrNull(ref.heading),
      timestamp: (ref.timestamp ?? _clock.now()),
      usedSamples: kept.length,
      discardedSamples: discardedCount + (bucket.length - kept.length),
    );
  }

  // DR corto
  LocationFix _extrapolate(LocationFix fix, {required Duration after}) {
    final v = fix.speedMps ?? 0;
    final hdg = fix.headingDeg ?? 0;
    final d = v * after.inMilliseconds / 1000.0; // metros
    if (d <= 0) return fix;
    final offset = _offsetMeters(fix.latitude, fix.longitude, d, hdg);
    final acc = ((fix.accuracyMeters ?? 10) + d * 0.2);
    return fix.copyWith(
      latitude: offset.$1,
      longitude: offset.$2,
      accuracyMeters: acc,
      timestamp: fix.timestamp.add(after),
    );
  }

  (double, double) _offsetMeters(double lat, double lng, double meters, double bearingDeg) {
    // Destino geodésico sobre esfera.
    const R = 6371000.0;
    final br = bearingDeg * math.pi / 180.0;
    final dr = meters / R;
    final lat1 = lat * math.pi / 180.0;
    final lng1 = lng * math.pi / 180.0;

    final sinLat2 =
        math.sin(lat1) * math.cos(dr) + math.cos(lat1) * math.sin(dr) * math.cos(br);
    final lat2 = math.asin(sinLat2);
    final y = math.sin(br) * math.sin(dr) * math.cos(lat1);
    final x = math.cos(dr) - math.sin(lat1) * math.sin(lat2);
    final lng2 = lng1 + math.atan2(y, x);

    return (lat2 * 180.0 / math.pi, lng2 * 180.0 / math.pi);
  }

  void _logError(Object e, StackTrace st) {
    debugPrint('LocationService error: $e');
    debugPrintStack(stackTrace: st);
  }
}

// ---------- helpers globales ----------
bool _isValid(double lat, double lng) =>
    lat.isFinite &&
        lng.isFinite &&
        (lat.abs() > 1e-6 || lng.abs() > 1e-6) &&
        lat.abs() <= 90 &&
        lng.abs() <= 180;

String _fmt(double v) => v.toStringAsFixed(6);

Uri _geoUri(double lat, double lng, {String? label}) {
  final q = (label == null || label.trim().isEmpty)
      ? '${_fmt(lat)},${_fmt(lng)}'
      : '${_fmt(lat)},${_fmt(lng)}(${Uri.encodeComponent(label)})';
  // Formato más compatible: geo:0,0?q=lat,lng(label)
  return Uri.parse('geo:0,0?q=$q');
}

// Google Maps (construcción segura)
Uri _mapsUri(double lat, double lng) => Uri.https(
  'www.google.com',
  '/maps/search/',
  {
    'api': '1',
    'query': '${_fmt(lat)},${_fmt(lng)}',
  },
);
