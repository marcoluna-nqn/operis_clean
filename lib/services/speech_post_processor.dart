// lib/services/speech_post_processor.dart

/// Abstracción de posprocesado de texto para STT.
/// Permite enchufar reglas por idioma o dominio.
abstract class SpeechPostProcessor {
  /// Limpia/normaliza texto parcial (se llama muchas veces).
  String onPartial(String text);

  /// Limpia/normaliza texto final (una vez terminado el dictado).
  String onFinal(String text);
}

/// Implementación por defecto:
/// - Normaliza espacios
/// - Arregla espacios alrededor de puntuación
/// - Capitaliza inicio de oración
/// - Asegura punto final si corresponde (sin romper números/horas)
class DefaultPostProcessor implements SpeechPostProcessor {
  static final RegExp _spaces = RegExp(r'\s+');
  static final RegExp _punctEnd = RegExp(r'[.!?…]\s*$');
  static final RegExp _spaceBeforePunct = RegExp(r'\s+([,.!?…:;])');

  // Inserta espacio después de ! ? … ; si falta
  static final RegExp _noSpaceAfterPunctGeneral = RegExp(r'([!?…;])([^\s])');

  // Inserta espacio después de ":" salvo que tenga dígitos a ambos lados (evita 10:30)
  // (sin lookbehind): captura inicio o no-dígito antes, ":" y no-espacio/no-dígito después
  static final RegExp _noSpaceAfterColon = RegExp(r'(^|[^\d])(:)([^\s\d])');

  // Inserta espacio después de "," o "." salvo que esté entre dígitos (evita 1.234 o 3,14)
  static final RegExp _noSpaceAfterCommaDot = RegExp(r'(^|[^\d])([.,])([^\s\d])');

  // Heurística: solo añadir punto final si termina “como oración”
  static final RegExp _needsSentenceEnd =
  RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9)\]"»]$');

  /// Helper público: detecta si termina en puntuación.
  static bool endsWithPunctuation(String s) => _punctEnd.hasMatch(s);

  /// Helper público: capitaliza primer letra respetando espacios iniciales.
  static String capitalize(String s) {
    if (s.isEmpty) return s;
    final trimmed = s.trimLeft();
    if (trimmed.isEmpty) return s;
    final start = s.length - trimmed.length;
    return s.replaceRange(start, start + 1, trimmed[0].toUpperCase());
  }

  /// Normalización base compartida.
  String _normalize(String s) {
    if (s.isEmpty) return s;
    var t = s.replaceAll('\u00A0', ' ');         // NBSP → espacio
    t = t.replaceAll(_spaces, ' ').trim();       // colapsa espacios
    t = t.replaceAll(_spaceBeforePunct, r'$1');  // quita espacio antes de puntuación

    // Asegura espacio después de ciertas puntuaciones (sin romper números/horas)
    t = t.replaceAllMapped(_noSpaceAfterPunctGeneral, (m) => '${m[1]} ${m[2]}');
    t = t.replaceAllMapped(_noSpaceAfterColon,       (m) => '${m[1]}${m[2]} ${m[3]}');
    t = t.replaceAllMapped(_noSpaceAfterCommaDot,    (m) => '${m[1]}${m[2]} ${m[3]}');

    return t.trim();
  }

  @override
  String onPartial(String text) {
    // Parciales: NO forzamos punto final; solo limpieza rápida.
    final t = _normalize(text);
    return t.isEmpty ? '' : t;
  }

  @override
  String onFinal(String text) {
    var t = _normalize(text);
    if (t.isEmpty) return t;

    // Capitaliza si parece inicio de oración.
    t = capitalize(t);

    // Punto final si falta y “luce” como oración.
    if (_needsSentenceEnd.hasMatch(t) && !endsWithPunctuation(t)) {
      t = '$t.';
    }

    // Limpieza final de espacios de cierre.
    return t.trimRight();
  }
}
