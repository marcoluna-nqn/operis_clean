// lib/services/firebase_test_service.dart
import 'package:flutter/foundation.dart';

class FirebaseTestService {
  /// Stub: Firebase deshabilitado. Siempre devuelve false.
  static Future<bool> testConnection() async {
    if (kDebugMode) {
      debugPrint(
          'FirebaseTestService: Firebase estÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¡ deshabilitado (stub).');
    }
    return false;
  }
}
