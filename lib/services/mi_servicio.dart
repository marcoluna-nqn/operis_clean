// lib/services/mi_servicio.dart
import 'dart:async';
import 'package:bitacora/models/measurement.dart';

/// Simula una API de paginación “siguiente página”.
class MiServicio {
  /// Devuelve la siguiente página (mock). Reemplazá con tu lógica real.
  static Future<List<Measurement>> fetchNextBatch() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return <Measurement>[]; // próximos registros
  }
}
