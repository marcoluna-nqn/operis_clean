// lib/services/firebase_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stub local que reemplaza a Cloud Firestore.
/// Guarda/lee "planillas" en SharedPreferences bajo la clave [_kKey].
class FirebaseService {
  static const _kKey = 'planillas_local_v1';

  static Future<void> savePlanilla(Map<String, dynamic> planilla) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kKey);
    final list = <Map<String, dynamic>>[];

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded) {
            if (e is Map) list.add(Map<String, dynamic>.from(e));
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Stub FirebaseService decode error: $e');
      }
    }

    // InsertÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¡ primero para ver lo mÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¡s nuevo arriba.
    list.insert(0, Map<String, dynamic>.from(planilla));
    await sp.setString(_kKey, jsonEncode(list));
  }

  static Future<List<Map<String, dynamic>>> obtenerPlanillas() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Stub FirebaseService decode error: $e');
    }
    return [];
  }
}
