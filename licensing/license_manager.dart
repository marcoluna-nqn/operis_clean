// lib/licensing/license_manager.dart
// Trial 1 mes calendario + licencias firmadas Ed25519 (BN2 con payload JSON).
//
// Formato BN2 emitido por tool/license_gen.dart:
//   BN2.<PAYLOAD_B64URL>.<SIGNATURE_B64URL>
//   payload (utf8) = JSON: {"v":2,"exp":<epoch_ms>,"dev":"ANY"|"<DEVICE_ID>"}
//   firma = Ed25519(payload_bytes)
//
// Compat: también acepta BN-YYYYMMDD-XXXXXXXX (legacy).
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptography/cryptography.dart' as crypto;

enum LicenseStatus { trial, valid, expired, invalid }

class LicenseState {
  final LicenseStatus status;
  final DateTime? expiresAt;
  final String? code;
  const LicenseState({required this.status, required this.expiresAt, this.code});
  LicenseState copyWith({LicenseStatus? status, DateTime? expiresAt, String? code}) =>
      LicenseState(status: status ?? this.status, expiresAt: expiresAt ?? this.expiresAt, code: code ?? this.code);
}

class LicenseManager {
  LicenseManager._();
  static final LicenseManager instance = LicenseManager._();

  /// ⚠️ Poné acá tu **pública** (Base64 o Base64URL).
  static const String kEd25519PublicKeyB64 =
      'Wy0upfzD5Izzqb7l5R8kCo2QoOajOBiK0n0XJMtJf4w=';

  static const _kInstallTsMs = 'lic_install_ts_ms';
  static const _kLicenseExpiryMs = 'lic_expiry_ms';
  static const _kLicenseCode = 'lic_code';
  static const _kLastInvalidFlag = 'lic_last_invalid';
  static const _kDeviceId = 'lic_device_id';

  SharedPreferences? _prefs;
  LicenseState _state = const LicenseState(status: LicenseStatus.trial, expiresAt: null);
  LicenseState get state => _state;

  int get daysLeft {
    final exp = _state.expiresAt;
    if (exp == null) return 0;
    final now = DateTime.now();
    final diff = exp.difference(DateTime(now.year, now.month, now.day)).inDays;
    return diff < 0 ? 0 : diff + 1;
  }

  bool get isExpired => _state.status == LicenseStatus.expired || _state.status == LicenseStatus.invalid;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    final now = DateTime.now();
    final installMs = _prefs!.getInt(_kInstallTsMs);
    final installAt = installMs != null ? DateTime.fromMillisecondsSinceEpoch(installMs) : now;
    if (installMs == null) {
      await _prefs!.setInt(_kInstallTsMs, installAt.millisecondsSinceEpoch);
    }

    // Trial: exactamente 1 mes calendario desde la instalación (a las 23:59:59)
    final trialExpiry = _addOneCalendarMonth(
      DateTime(installAt.year, installAt.month, installAt.day),
    );

    final licMs = _prefs!.getInt(_kLicenseExpiryMs);
    final licExpiry = licMs != null ? DateTime.fromMillisecondsSinceEpoch(licMs) : null;
    final licCode = _prefs!.getString(_kLicenseCode);

    LicenseStatus status;
    DateTime? effectiveExpiry;
    if (licExpiry != null && licExpiry.isAfter(now)) {
      status = LicenseStatus.valid;
      effectiveExpiry = licExpiry;
    } else if (trialExpiry.isAfter(now)) {
      status = LicenseStatus.trial;
      effectiveExpiry = trialExpiry;
    } else {
      status = LicenseStatus.expired;
      effectiveExpiry = licExpiry ?? trialExpiry;
    }

    if (_prefs!.getBool(_kLastInvalidFlag) == true) {
      status = LicenseStatus.invalid;
      await _prefs!.remove(_kLastInvalidFlag);
    }

    _state = LicenseState(status: status, expiresAt: effectiveExpiry, code: licCode);
  }

  Future<bool> applyLicense(String raw) async {
    final code = raw.trim();

    // BN2.<payload>.<sig>
    if (code.startsWith('BN2.')) {
      final ok = await _applySigned(code);
      if (!ok) await _markInvalid();
      return ok;
    }

    // Legacy: BN-YYYYMMDD-XXXXXXXX
    final legacy = _parseLegacy(code);
    if (legacy != null && legacy.expiresAt.isAfter(DateTime.now())) {
      await _accept(expiry: legacy.expiresAt, code: legacy.normalized);
      return true;
    }

    await _markInvalid();
    return false;
  }

  Future<void> clearLicense() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.remove(_kLicenseExpiryMs);
    await _prefs!.remove(_kLicenseCode);
    await init();
  }

  Future<bool> _applySigned(String code) async {
    try {
      // BN2.<PAYLOAD_B64URL>.<SIG_B64URL>
      final parts = code.split('.');
      if (parts.length != 3 || parts[0] != 'BN2') return false;

      final payloadB64 = parts[1];
      final sigB64 = parts[2];

      final payloadBytes = _b64urlDecode(payloadB64);
      final sigBytes = _b64urlDecode(sigB64);
      final pubKeyBytes = _b64urlDecode(kEd25519PublicKeyB64);
      if (payloadBytes == null || sigBytes == null || pubKeyBytes == null) return false;

      final algo = crypto.Ed25519();
      final publicKey = crypto.SimplePublicKey(pubKeyBytes, type: crypto.KeyPairType.ed25519);
      final ok = await algo.verify(payloadBytes, signature: crypto.Signature(sigBytes, publicKey: publicKey));
      if (!ok) return false;

      // Parsear JSON del payload
      final payload = jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;
      final ver = payload['v'] as int? ?? 0;
      final expMs = payload['exp'] as int?;
      final dev = payload['dev'] as String? ?? 'ANY';
      if (ver != 2 || expMs == null) return false;

      final expiry = DateTime.fromMillisecondsSinceEpoch(expMs);
      if (!expiry.isAfter(DateTime.now())) return false;

      final myDevice = await _deviceId();
      final deviceOk = dev == 'ANY' || dev == myDevice;
      if (!deviceOk) return false;

      await _accept(expiry: expiry, code: code);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _accept({required DateTime expiry, required String code}) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_kLicenseExpiryMs, expiry.millisecondsSinceEpoch);
    await _prefs!.setString(_kLicenseCode, code);
    await _prefs!.remove(_kLastInvalidFlag);
    _state = LicenseState(status: LicenseStatus.valid, expiresAt: expiry, code: code);
  }

  Future<void> _markInvalid() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_kLastInvalidFlag, true);
    _state = _state.copyWith(status: LicenseStatus.invalid);
  }

  _ParsedLegacy? _parseLegacy(String input) {
    final code = input.trim().toUpperCase();
    final reg = RegExp(r'^BN-(\d{8})-([A-Z0-9]{8,})$');
    final m = reg.firstMatch(code);
    if (m == null) return null;
    final yyyymmdd = m.group(1)!;
    final y = int.parse(yyyymmdd.substring(0, 4));
    final mo = int.parse(yyyymmdd.substring(4, 6));
    final d = int.parse(yyyymmdd.substring(6, 8));
    try {
      final exp = DateTime(y, mo, d, 23, 59, 59);
      return _ParsedLegacy(normalized: code, expiresAt: exp);
    } catch (_) {
      return null;
    }
  }

  Future<String> _deviceId() async {
    _prefs ??= await SharedPreferences.getInstance();
    final existing = _prefs!.getString(_kDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;

    final rnd = Random();
    String hex(int n) => List<int>.generate(n, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final id = 'AD-${DateTime.now().millisecondsSinceEpoch}-${hex(6)}';
    await _prefs!.setString(_kDeviceId, id);
    return id;
  }

  Uint8List? _b64urlDecode(String s) {
    try {
      var t = s.replaceAll('-', '+').replaceAll('_', '/');
      while (t.length % 4 != 0) {
        t += '=';
      }
      return Uint8List.fromList(base64Decode(t));
    } catch (_) {
      return null;
    }
  }

  // === Trial de 1 mes calendario ===
  DateTime _addOneCalendarMonth(DateTime d) {
    final y2 = (d.month == 12) ? d.year + 1 : d.year;
    final m2 = (d.month == 12) ? 1 : d.month + 1;

    int daysInMonth(int yy, int mm) {
      final firstNext = (mm < 12) ? DateTime(yy, mm + 1, 1) : DateTime(yy + 1, 1, 1);
      return firstNext.subtract(const Duration(days: 1)).day;
    }

    final lastDay = daysInMonth(y2, m2);
    final day = d.day <= lastDay ? d.day : lastDay; // clampa 29/30/31
    return DateTime(y2, m2, day, 23, 59, 59);
  }
}

class _ParsedLegacy {
  final String normalized;
  final DateTime expiresAt;
  _ParsedLegacy({required this.normalized, required this.expiresAt});
}
