// lib/services/auth_service.dart

/// Stub de autenticación sin Firebase.
/// - Si [allowedEmails] está vacío, permite el acceso sin validar.
/// - Si hay whitelist, validá contra [email] (pasado desde tu UI).
class AuthService {
  static Future<void> signInWithGoogle(
      List<String> allowedEmails, {
        String? email, // pásalo desde tu UI si querés validar
      }) async {
    if (allowedEmails.isEmpty) return;

    final e = (email ?? '').toLowerCase().trim();
    if (e.isEmpty) {
      throw Exception('Falta email para validar (stub sin Firebase).');
    }

    final allow =
    allowedEmails.map((x) => x.toLowerCase().trim()).toSet();
    if (!allow.contains(e)) {
      throw Exception(
        'Este correo no está autorizado para usar la aplicación.',
      );
    }
  }

  static Future<void> signOut() async {
    // No-op en stub (no hay sesión real que cerrar)
  }
}
