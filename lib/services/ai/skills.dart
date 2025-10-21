// lib/services/ai/skills.dart
class CopilotContext {
  const CopilotContext();
}

abstract class CopilotSkill {
  String get name;

  /// Devuelve cualquier payload serializable (Map recomendado).
  Future<dynamic> invoke(CopilotContext ctx);

  /// 0..1 según calidad del output para este contexto.
  double confidence(CopilotContext ctx, dynamic output);
}

// --------- Skills de ejemplo usados por Copilot ---------

class OcrSkill implements CopilotSkill {
  @override
  String get name => 'ocr';

  @override
  Future<dynamic> invoke(CopilotContext ctx) async {
    // Stub seguro. Si tenés OCR real, reemplazá esto.
    return <String, dynamic>{'bestLine': null, 'tags': const <String>[]};
  }

  @override
  double confidence(CopilotContext ctx, dynamic out) {
    final best = (out is Map) ? out['bestLine'] : null;
    return (best is String && best.trim().isNotEmpty) ? 0.8 : 0.2;
  }
}

class ObjectsSkill implements CopilotSkill {
  @override
  String get name => 'objects';

  @override
  Future<dynamic> invoke(CopilotContext ctx) async {
    return <String, dynamic>{'topClass': null, 'tags': const <String>[]};
  }

  @override
  double confidence(CopilotContext ctx, dynamic out) {
    final top = (out is Map) ? out['topClass'] : null;
    return (top is String && top.trim().isNotEmpty) ? 0.7 : 0.2;
  }
}

class GpsSkill implements CopilotSkill {
  @override
  String get name => 'gps';

  @override
  Future<dynamic> invoke(CopilotContext ctx) async {
    return <String, dynamic>{'lat': null, 'lng': null, 'acc': 30.0};
  }

  @override
  double confidence(CopilotContext ctx, dynamic out) {
    final ok = out is Map && out['lat'] is num && out['lng'] is num;
    return ok ? 0.9 : 0.2;
  }
}

class MemorySkill implements CopilotSkill {
  MemorySkill(this.loader);
  final Future<Map<String, dynamic>> Function() loader;

  @override
  String get name => 'memory';

  @override
  Future<dynamic> invoke(CopilotContext ctx) async => await loader();

  @override
  double confidence(CopilotContext ctx, dynamic out) => 0.6;
}
