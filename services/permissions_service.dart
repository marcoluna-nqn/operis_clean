// lib/services/permissions_service.dart
import 'dart:io' show Platform;
import 'package:geolocator/geolocator.dart';

typedef Rationale = Future<bool> Function();      // mostrar por qué se pide; true=proceder
typedef OnSettings = Future<void> Function();     // UI para guiar a Ajustes/Settings

class PermissionsService {
  PermissionsService._();
  static final PermissionsService instance = PermissionsService._();

  /// Verifica que el servicio de ubicación del dispositivo esté activo.
  /// Si [openSettingsIfOff] es true, intenta abrir Ajustes y re-chequear.
  Future<bool> ensureLocationServiceOn({
    bool openSettingsIfOff = true,
    OnSettings? onOpenSettings,
  }) async {
    if (await Geolocator.isLocationServiceEnabled()) return true;
    if (!openSettingsIfOff) return false;

    // UI opcional antes de abrir Ajustes
    if (onOpenSettings != null) await onOpenSettings();
    await Geolocator.openLocationSettings();

    // pequeño margen para volver de Ajustes
    await Future.delayed(const Duration(milliseconds: 300));
    return Geolocator.isLocationServiceEnabled();
  }

  /// Pide o verifica permisos de ubicación de primer plano (whileInUse).
  /// - Muestra [onRationale] si el SO lo requiere (o si lo deseas antes de pedir).
  /// - Si está "deniedForever", intenta guiar a Ajustes (onOpenSettings + openAppSettings).
  Future<bool> ensureLocationWhenInUse({
    Rationale? onRationale,
    OnSettings? onOpenSettings,
  }) async {
    var status = await Geolocator.checkPermission();

    if (status == LocationPermission.denied) {
      if (onRationale != null) {
        final go = await onRationale();
        if (!go) return false;
      }
      status = await Geolocator.requestPermission();
    }

    if (status == LocationPermission.deniedForever) {
      if (onOpenSettings != null) await onOpenSettings();
      await Geolocator.openAppSettings();
      await Future.delayed(const Duration(milliseconds: 300));
      status = await Geolocator.checkPermission();
    }

    return status == LocationPermission.whileInUse ||
        status == LocationPermission.always;
  }

  /// Intenta elevar a permiso de **segundo plano** (always).
  /// En Android suele requerir Ajustes. En iOS puede pedir una segunda vez si el Info.plist está correcto.
  Future<bool> ensureLocationAlways({
    Rationale? onRationale,
    OnSettings? onOpenSettings,
  }) async {
    // Asegura whileInUse primero
    final fgOk = await ensureLocationWhenInUse(
      onRationale: onRationale,
      onOpenSettings: onOpenSettings,
    );
    if (!fgOk) return false;

    var status = await Geolocator.checkPermission();
    if (status == LocationPermission.always) return true;

    // Intento de solicitud (iOS puede mostrar "Always" si está configurado)
    if (onRationale != null) {
      final go = await onRationale();
      if (!go) return false;
    }
    status = await Geolocator.requestPermission();

    if (status == LocationPermission.always) return true;

    // Guía a Ajustes para seleccionar "Allow all the time" (Android) / Always (iOS)
    if (onOpenSettings != null) await onOpenSettings();
    await Geolocator.openAppSettings();
    await Future.delayed(const Duration(milliseconds: 300));
    status = await Geolocator.checkPermission();

    return status == LocationPermission.always;
  }

  /// En iOS 14+ puede existir precisión reducida. Intenta pedir precisión completa temporal.
  /// Requiere `NSLocationTemporaryUsageDescriptionDictionary` con la clave [purposeKey] en Info.plist.
  Future<bool> ensurePreciseAccuracyIOS({required String purposeKey}) async {
    if (!Platform.isIOS) return true;
    final acc = await Geolocator.getLocationAccuracy();
    if (acc == LocationAccuracyStatus.precise) return true;

    final ok = await Geolocator.requestTemporaryFullAccuracy(purposeKey: purposeKey);
    return ok == LocationAccuracyStatus.precise;
  }

  /// Flujo completo recomendado:
  /// 1) Servicio ON  2) WhileInUse  3) (opcional) Always  4) (opcional) Precise iOS
  Future<bool> ensureLocationPermission({
    bool requireAlways = false,
    bool requirePreciseIOS = false,
    String precisePurposeKeyIOS = 'LocationPrecise',
    Rationale? onRationale,
    OnSettings? onOpenSettings,
    bool openSettingsIfServiceOff = true,
  }) async {
    final serviceOn = await ensureLocationServiceOn(
      openSettingsIfOff: openSettingsIfServiceOff,
      onOpenSettings: onOpenSettings,
    );
    if (!serviceOn) return false;

    final fgOk = await ensureLocationWhenInUse(
      onRationale: onRationale,
      onOpenSettings: onOpenSettings,
    );
    if (!fgOk) return false;

    if (requireAlways) {
      final bgOk = await ensureLocationAlways(
        onRationale: onRationale,
        onOpenSettings: onOpenSettings,
      );
      if (!bgOk) return false;
    }

    if (requirePreciseIOS) {
      final preciseOk = await ensurePreciseAccuracyIOS(purposeKey: precisePurposeKeyIOS);
      if (!preciseOk) return false;
    }

    return true;
  }
}
