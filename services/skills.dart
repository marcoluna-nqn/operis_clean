// lib/services/ai/skills.dart
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';

class CopilotContext {
  // acÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¡ podÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©s inyectar cÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¡mara, mini-LLM, caches, etc.
  CopilotContext();
}

abstract class CopilotSkill {
  String get name;
  Future<Map<String, dynamic>> invoke(CopilotContext ctx);
  double confidence(CopilotContext ctx, Map<String, dynamic> out);
}

/// OCR rÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¡pido (MLKit) ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ placeholder
class OcrSkill implements CopilotSkill {
  @override
  String get name => 'ocr';

  @override
  Future<Map<String, dynamic>> invoke(CopilotContext ctx) async {
    // TODO: MLKit TextRecognizer. Placeholder:
    return {
      'bestLine': 'Poste 124 sin aislador',
      'tags': ['poste', 'aislador']
    };
  }

  @override
  double confidence(_, out) => out['bestLine'] == null ? 0.0 : 0.78;
}

/// Detector objetos (TFLite/YOLO int8) ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ placeholder
class ObjectsSkill implements CopilotSkill {
  @override
  String get name => 'objects';

  @override
  Future<Map<String, dynamic>> invoke(CopilotContext ctx) async {
    // TODO: TFLite. Placeholder:
    return {
      'topClass': 'Rotura leve',
      'tags': ['rotura', 'cable', 'poste']
    };
  }

  @override
  double confidence(_, __) => 0.72;
}

/// GPS robusto usando Geolocator (warm-up corto + best fix)
class GpsSkill implements CopilotSkill {
  @override
  String get name => 'gps';

  @override
  Future<Map<String, dynamic>> invoke(CopilotContext ctx) async {
    // Servicios y permisos
    if (!await Geolocator.isLocationServiceEnabled()) {
      return {'error': 'gps_disabled'};
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return {'error': 'no_permission'};
    }

    // Warm-up: encender proveedores y recolectar el mejor fix por unos segundos
    final best = _BestFixCollector();
    final sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      ),
    ).listen(best.add, onError: (_) {});

    try {
      // Dejar correr un poco para calentar hardware/cache
      await Future<void>.delayed(const Duration(seconds: 5));

      // Intento puntual con timeout para mejorar exactitud
      try {
        final p = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 10),
        );
        best.add(p);
      } catch (_) {
        // ignorado: nos quedamos con lo mejor del stream
      }
    } finally {
      await sub.cancel();
    }

    final pos = best.best ?? await Geolocator.getLastKnownPosition();
    if (pos == null) return {'error': 'no_fix'};

    return {
      'lat': pos.latitude,
      'lng': pos.longitude,
      'acc': pos.accuracy, // metros 1-sigma aprox
      'provider': 'geolocator',
    };
  }

  @override
  double confidence(_, out) {
    final acc = (out['acc'] as num?)?.toDouble() ?? 99.0;
    // 0 m => 1.0 ; 60 m => 0.0
    final v = 1.0 - (math.min(acc, 60.0) / 60.0);
    return v.clamp(0.0, 1.0);
  }
}

/// Memoria (aprendizajes/correcciones de usuario)
class MemorySkill implements CopilotSkill {
  final Future<Map<String, dynamic>> Function() loader;
  MemorySkill(this.loader);

  @override
  String get name => 'memory';

  @override
  Future<Map<String, dynamic>> invoke(CopilotContext ctx) => loader();

  @override
  double confidence(_, __) => 0.6;
}

/// Selecciona el mejor fix por precisiÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³n.
class _BestFixCollector {
  Position? best;

  void add(Position p) {
    if (best == null || p.accuracy <= best!.accuracy) {
      best = p;
    }
  }
}
