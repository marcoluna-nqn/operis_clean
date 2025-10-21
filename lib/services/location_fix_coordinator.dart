// lib/services/location_fix_coordinator.dart
// Coordina lecturas para evitar (0,0), reusar fixes buenos y mejorar en 2º plano.
// Requiere: location_service.dart (CancelToken, LocationFix, LocationService) + geo_utils.dart

import 'dart:async';
import 'package:flutter/foundation.dart' show ValueNotifier, ValueListenable;
import '../utils/geo_utils.dart';
import 'location_service.dart';

class LocationFixCoordinator {
  LocationFixCoordinator._();
  static final LocationFixCoordinator instance = LocationFixCoordinator._();

  LocationFix? _lastGood;
  Completer<LocationFix>? _inflight;
  final ValueNotifier<LocationFix?> lastGoodListenable = ValueNotifier<LocationFix?>(null);

  /// Fix único y válido, con:
  /// - Reuso por tiempo, precisión y distancia estimada recorrida.
  /// - Lectura serializada (comparte inflight).
  /// - Upgrade opcional en segundo plano.
  Future<LocationFix> getFix({
    // Reuso
    Duration reuseFor = const Duration(seconds: 12),
    double maxReuseAccuracy = 35.0,
    double maxReuseDistanceMeters = 10.0,
    // Lectura
    int retries = 1,
    Duration overallTimeout = const Duration(seconds: 12),
    bool preferAdaptive = true,
    // Callbacks / control
    CancelToken? cancelToken,
    void Function(LocationFix better)? onUpgrade,
  }) async {
    // 1) Reusar último bueno si aplica.
    final lg = _lastGood;
    if (_shouldReuse(lg, reuseFor, maxReuseAccuracy, maxReuseDistanceMeters)) {
      // Disparar upgrade sin bloquear.
      _tryUpgradeInBackground(onUpgrade: onUpgrade);
      return lg!;
    }

    // 2) Compartir inflight si existe.
    final existing = _inflight;
    if (existing != null) return existing.future;

    // 3) Nueva lectura serializada con timeout total.
    final c = Completer<LocationFix>();
    _inflight = c;

    // Reloj de timeout total.
    Timer? killer;
    bool timedOut = false;
    if (overallTimeout > Duration.zero) {
      killer = Timer(overallTimeout, () {
        timedOut = true;
        if (!c.isCompleted) {
          c.completeError(const LocationException('Timeout total en getFix'));
        }
      });
    }

    () async {
      try {
        final r = preferAdaptive
            ? await _readAdaptive(cancelToken: cancelToken)
            : await _readPrecise(cancelToken: cancelToken);
        if (!timedOut && !_isValid(r)) {
          throw const LocationException('Fix inválido');
        }
        if (!timedOut && !c.isCompleted) {
          _setLastGood(r);
          c.complete(r);
          // Upgrade si aún no es lo bastante preciso.
          if ((r.accuracyMeters ?? 9999) > maxReuseAccuracy) {
            _tryUpgradeInBackground(onUpgrade: onUpgrade);
          }
        }
      } catch (e) {
        // Reintentos cortos con backoff.
        if (timedOut) return;
        for (var i = 0; i < retries; i++) {
          await Future<void>.delayed(Duration(milliseconds: 250 * (i + 1)));
          try {
            final r = await _readPrecise(cancelToken: cancelToken);
            if (!timedOut && !c.isCompleted) {
              _setLastGood(r);
              c.complete(r);
            }
            return;
          } catch (_) {
            // último intento
            if (i == retries - 1 && !timedOut && !c.isCompleted) {
              final fallback = _lastGood;
              if (fallback != null) {
                c.complete(fallback);
              } else {
                c.completeError(e);
              }
            }
          }
        }
      } finally {
        killer?.cancel();
        _inflight = null;
      }
    }();

    return c.future;
  }

  /// Igual que [getFix] pero devuelve null si falla.
  Future<LocationFix?> getFixOrNull({
    Duration reuseFor = const Duration(seconds: 12),
    double maxReuseAccuracy = 35.0,
    double maxReuseDistanceMeters = 10.0,
    int retries = 1,
    Duration overallTimeout = const Duration(seconds: 12),
    bool preferAdaptive = true,
    CancelToken? cancelToken,
    void Function(LocationFix better)? onUpgrade,
  }) async {
    try {
      return await getFix(
        reuseFor: reuseFor,
        maxReuseAccuracy: maxReuseAccuracy,
        maxReuseDistanceMeters: maxReuseDistanceMeters,
        retries: retries,
        overallTimeout: overallTimeout,
        preferAdaptive: preferAdaptive,
        cancelToken: cancelToken,
        onUpgrade: onUpgrade,
      );
    } catch (_) {
      return null;
    }
  }

  /// Warm-up del caché sin bloquear pantallas. Ignora errores.
  Future<void> prefetch({bool preferAdaptive = true}) async {
    if (_inflight != null) return;
    try {
      await getFix(preferAdaptive: preferAdaptive, retries: 0);
    } catch (_) {}
  }

  /// Permite inyectar un fix conocido (p.ej. de otra pantalla).
  void prime(LocationFix fix) {
    if (_isValid(fix)) _setLastGood(fix);
  }

  /// Invalida manualmente el caché.
  void invalidate() {
    _lastGood = null;
    lastGoodListenable.value = null;
  }

  // ---------------- internals ----------------

  bool _shouldReuse(
      LocationFix? f,
      Duration reuseFor,
      double maxReuseAccuracy,
      double maxReuseDistanceMeters,
      ) {
    if (f == null) return false;
    if (!_isValid(f)) return false;

    final age = DateTime.now().difference(f.timestamp);
    if (age > reuseFor) return false;

    final accOk = (f.accuracyMeters ?? 9999) <= maxReuseAccuracy;
    if (!accOk) return false;

    // Distancia esperada recorrida = speed * age
    final speed = f.speedMps ?? 0.0;
    final drift = speed * age.inMilliseconds / 1000.0;
    if (drift > maxReuseDistanceMeters) return false;

    return true;
  }

  void _setLastGood(LocationFix fix) {
    _lastGood = fix;
    lastGoodListenable.value = fix;
  }

  // Upgrade de precisión en segundo plano, sin bloquear llamadas.
  void _tryUpgradeInBackground({void Function(LocationFix better)? onUpgrade}) {
    if (_inflight != null) return; // ya hay lectura en curso
    scheduleMicrotask(() async {
      try {
        final better = await _readPrecise();
        if (_isValid(better)) {
          _setLastGood(better);
          if (onUpgrade != null) onUpgrade(better);
        }
      } catch (_) {}
    });
  }

  Future<LocationFix> _readAdaptive({CancelToken? cancelToken}) {
    return LocationService.instance.getAdaptiveFix(
      cancelToken: cancelToken,
      onBetterFix: (b) {
        if (_isValid(b)) _setLastGood(b);
      },
    );
  }

  Future<LocationFix> _readPrecise({CancelToken? cancelToken}) {
    // Aproxima timeout total: N * perSampleTimeout.
    return LocationService.instance.getPreciseFix(
      samples: 10,
      perSampleTimeout: const Duration(seconds: 2),
      keepBestFraction: 0.6,
      cancelToken: cancelToken,
    );
  }

  bool _isValid(LocationFix? f) {
    if (f == null) return false;
    return GeoUtils.isValid(f.latitude, f.longitude);
  }
}
