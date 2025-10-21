// lib/utils/strings.dart

/// Convierte cualquier valor a String de forma segura.
/// - null -> fallback ('' por defecto)
/// - Object/dynamic -> toString()
String asString(Object? v, {String fallback = ''}) => v?.toString() ?? fallback;

/// Normaliza un String nullable a no-nullable.
/// - null -> fallback ('' por defecto)
String nn(String? v, {String fallback = ''}) => v ?? fallback;
