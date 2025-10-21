// lib/services/license_manager.dart
// Stub minimal para compilar sin la implementación real de licencias.

class LicenseStatus {
  final bool hasValidLicense;
  final DateTime? expiresAtUtc;

  const LicenseStatus({
    required this.hasValidLicense,
    this.expiresAtUtc,
  });
}

class LicenseManager {
  const LicenseManager();

  /// Devuelve el estado actual (por defecto, sin licencia).
  Future<LicenseStatus> currentStatus() async {
    return const LicenseStatus(hasValidLicense: false, expiresAtUtc: null);
  }

  /// Activa la licencia. Lógica fake: acepta tokens de 12+ caracteres.
  Future<bool> activate(String token) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return token.trim().length >= 12;
  }
}
