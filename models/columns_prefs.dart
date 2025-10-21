// lib/models/columns_prefs.dart
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';

/// Rol semántico de la columna para funciones de negocio.
enum ColumnRole {
  normal,
  latitude,
  longitude,
  photos, // lista/ruta(s) de fotos
}

/// Tipo de dato preferido para exportación/validación.
enum ColumnType {
  text,
  number,
  dateTime,
  boolean,
}

@immutable
class ColumnDef {
  final String id;          // estable, p.ej. 'lat', 'lng', 'obs'
  final String label;       // visible para el usuario
  final ColumnRole role;    // semántica (lat/lng/etc.)
  final ColumnType type;    // tipado (text/number/datetime/bool)
  final bool visible;       // se muestra en UI/tabla
  final int order;          // posición (0-based)

  const ColumnDef({
    required this.id,
    required this.label,
    this.role = ColumnRole.normal,
    this.type = ColumnType.text,
    this.visible = true,
    required this.order,
  });

  ColumnDef copyWith({
    String? id,
    String? label,
    ColumnRole? role,
    ColumnType? type,
    bool? visible,
    int? order,
  }) {
    return ColumnDef(
      id: id ?? this.id,
      label: label ?? this.label,
      role: role ?? this.role,
      type: type ?? this.type,
      visible: visible ?? this.visible,
      order: order ?? this.order,
    );
  }

  factory ColumnDef.fromJson(Map<String, dynamic> j) {
    return ColumnDef(
      id: j['id'] as String,
      label: j['label'] as String,
      role: _roleFrom(j['role']),
      type: _typeFrom(j['type']),
      visible: (j['visible'] as bool?) ?? true,
      order: (j['order'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'role': role.name,
    'type': type.name,
    'visible': visible,
    'order': order,
  };

  static ColumnRole _roleFrom(Object? v) {
    final s = (v ?? 'normal').toString();
    return ColumnRole.values.firstWhere(
          (e) => e.name == s,
      orElse: () => ColumnRole.normal,
    );
  }

  static ColumnType _typeFrom(Object? v) {
    final s = (v ?? 'text').toString();
    return ColumnType.values.firstWhere(
          (e) => e.name == s,
      orElse: () => ColumnType.text,
    );
  }

  // Importante para poder comparar listas de ColumnDef sin mapear a JSON.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ColumnDef &&
        other.id == id &&
        other.label == label &&
        other.role == role &&
        other.type == type &&
        other.visible == visible &&
        other.order == order;
  }

  @override
  int get hashCode => Object.hash(id, label, role, type, visible, order);
}

@immutable
class ColumnsPrefs {
  /// Versión del esquema JSON: v2 introduce ColumnType y valida export.
  final int schemaVersion; // siempre 2 en el guardado actual
  final List<ColumnDef> columns;
  /// Columna 1-based donde se inserta la miniatura en el Excel principal.
  final int imageColumnIndex;

  const ColumnsPrefs({
    required this.schemaVersion,
    required this.columns,
    required this.imageColumnIndex,
  });

  ColumnsPrefs copyWith({
    int? schemaVersion,
    List<ColumnDef>? columns,
    int? imageColumnIndex,
  }) {
    return ColumnsPrefs(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      columns: columns ?? this.columns,
      imageColumnIndex: imageColumnIndex ?? this.imageColumnIndex,
    );
  }

  // ======= Defaults / Presets =======

  static ColumnsPrefs defaults() {
    final cols = <ColumnDef>[
      const ColumnDef(id: 'ts', label: 'Fecha', role: ColumnRole.normal, type: ColumnType.dateTime, order: 0),
      const ColumnDef(id: 'lat', label: 'Lat', role: ColumnRole.latitude, type: ColumnType.number, order: 1),
      const ColumnDef(id: 'lng', label: 'Lng', role: ColumnRole.longitude, type: ColumnType.number, order: 2),
      const ColumnDef(id: 'desc', label: 'Descripción', role: ColumnRole.normal, type: ColumnType.text, order: 3),
      const ColumnDef(id: 'fotos', label: 'Fotos', role: ColumnRole.photos, type: ColumnType.text, order: 4),
    ];
    return ColumnsPrefs(schemaVersion: 2, columns: cols, imageColumnIndex: 5 /* 1-based: 'Fotos' */);
  }

  static ColumnsPrefs workSitePreset() {
    final cols = <ColumnDef>[
      const ColumnDef(id: 'ts', label: 'Fecha', role: ColumnRole.normal, type: ColumnType.dateTime, order: 0),
      const ColumnDef(id: 'sector', label: 'Sector', role: ColumnRole.normal, type: ColumnType.text, order: 1),
      const ColumnDef(id: 'lat', label: 'Lat', role: ColumnRole.latitude, type: ColumnType.number, order: 2),
      const ColumnDef(id: 'lng', label: 'Lng', role: ColumnRole.longitude, type: ColumnType.number, order: 3),
      const ColumnDef(id: 'obs', label: 'Observaciones', role: ColumnRole.normal, type: ColumnType.text, order: 4),
      const ColumnDef(id: 'fotos', label: 'Fotos', role: ColumnRole.photos, type: ColumnType.text, order: 5),
    ];
    return ColumnsPrefs(schemaVersion: 2, columns: cols, imageColumnIndex: 6);
  }

  static ColumnsPrefs auditPreset() {
    final cols = <ColumnDef>[
      const ColumnDef(id: 'ts', label: 'Fecha', role: ColumnRole.normal, type: ColumnType.dateTime, order: 0),
      const ColumnDef(id: 'item', label: 'Ítem', role: ColumnRole.normal, type: ColumnType.text, order: 1),
      const ColumnDef(id: 'ok', label: 'OK', role: ColumnRole.normal, type: ColumnType.boolean, order: 2),
      const ColumnDef(id: 'lat', label: 'Lat', role: ColumnRole.latitude, type: ColumnType.number, order: 3),
      const ColumnDef(id: 'lng', label: 'Lng', role: ColumnRole.longitude, type: ColumnType.number, order: 4),
      const ColumnDef(id: 'nota', label: 'Nota', role: ColumnRole.normal, type: ColumnType.text, order: 5),
      const ColumnDef(id: 'fotos', label: 'Fotos', role: ColumnRole.photos, type: ColumnType.text, order: 6),
    ];
    return ColumnsPrefs(schemaVersion: 2, columns: cols, imageColumnIndex: 7);
  }

  // ======= JSON =======

  Map<String, dynamic> toJson() => {
    'schemaVersion': 2,
    'imageColumnIndex': imageColumnIndex,
    'columns': columns.map((e) => e.toJson()).toList(),
  };

  factory ColumnsPrefs.fromJson(Map<String, dynamic> j) {
    final v = (j['schemaVersion'] as num?)?.toInt() ?? 1;
    if (v == 2) {
      final cols = ((j['columns'] as List?) ?? const <dynamic>[])
          .map((e) => ColumnDef.fromJson(e as Map<String, dynamic>))
          .toList();
      final imgCol = (j['imageColumnIndex'] as num?)?.toInt() ?? (cols.length.clamp(1, cols.length));
      return ColumnsPrefs(schemaVersion: 2, columns: cols, imageColumnIndex: imgCol);
    }
    // Migración v1 -> v2
    return _migrateV1toV2(j);
  }

  static ColumnsPrefs _migrateV1toV2(Map<String, dynamic> j) {
    // Estructuras v1 esperables:
    // { columns: [{id,label,role,visible,order}], imageColumnIndex? }
    final raw = ((j['columns'] as List?) ?? const <dynamic>[]);
    final migrated = <ColumnDef>[];
    for (var i = 0; i < raw.length; i++) {
      final m = raw[i] as Map<String, dynamic>;
      final role = ColumnDef._roleFrom(m['role']);
      // Heurística para tipo
      ColumnType type = ColumnType.text;
      final label = (m['label'] as String? ?? '').toLowerCase();
      if (role == ColumnRole.latitude || role == ColumnRole.longitude) {
        type = ColumnType.number;
      } else if (label.contains('fecha') || label.contains('date')) {
        type = ColumnType.dateTime;
      } else if (label == 'ok' || label.contains('bool')) {
        type = ColumnType.boolean;
      }
      migrated.add(ColumnDef(
        id: m['id'] as String,
        label: m['label'] as String,
        role: role,
        type: type,
        visible: (m['visible'] as bool?) ?? true,
        order: (m['order'] as num?)?.toInt() ?? i,
      ));
    }
    final imgCol = (j['imageColumnIndex'] as num?)?.toInt() ?? (migrated.isEmpty ? 1 : migrated.length);
    return ColumnsPrefs(schemaVersion: 2, columns: migrated, imageColumnIndex: imgCol);
  }

  // ======= Utilidades de dominio =======

  /// Garantiza unicidad de lat/lng (si estableces una, limpia otra previa).
  ColumnsPrefs withRoleEnforced(String id, ColumnRole newRole) {
    if (newRole == ColumnRole.latitude || newRole == ColumnRole.longitude) {
      final cleared = columns.map((c) {
        if (c.id == id) return c.copyWith(role: newRole);
        if (newRole == ColumnRole.latitude && c.role == ColumnRole.latitude) {
          return c.copyWith(role: ColumnRole.normal);
        }
        if (newRole == ColumnRole.longitude && c.role == ColumnRole.longitude) {
          return c.copyWith(role: ColumnRole.normal);
        }
        return c;
      }).toList();
      return copyWith(columns: _reorderNormalize(cleared));
    }
    final updated = columns.map((c) => c.id == id ? c.copyWith(role: newRole) : c).toList();
    return copyWith(columns: _reorderNormalize(updated));
  }

  ColumnsPrefs rename(String id, String newLabel) {
    final updated = columns.map((c) => c.id == id ? c.copyWith(label: newLabel) : c).toList();
    return copyWith(columns: _reorderNormalize(updated));
  }

  ColumnsPrefs setType(String id, ColumnType t) {
    final updated = columns.map((c) => c.id == id ? c.copyWith(type: t) : c).toList();
    return copyWith(columns: _reorderNormalize(updated));
  }

  ColumnsPrefs setVisible(String id, bool v) {
    final updated = columns.map((c) => c.id == id ? c.copyWith(visible: v) : c).toList();
    return copyWith(columns: _reorderNormalize(updated));
  }

  ColumnsPrefs reorder(List<String> orderedIds) {
    final byId = {for (final c in columns) c.id: c};
    final out = <ColumnDef>[];
    var i = 0;
    for (final id in orderedIds) {
      final c = byId[id];
      if (c != null) out.add(c.copyWith(order: i++));
    }
    // agrega los que falten al final
    for (final c in columns) {
      if (!orderedIds.contains(c.id)) out.add(c.copyWith(order: i++));
    }
    return copyWith(columns: _reorderNormalize(out));
  }

  ColumnsPrefs addColumn(ColumnDef c) {
    final maxOrder = columns.isEmpty ? -1 : columns.map((e) => e.order).reduce((a, b) => a > b ? a : b);
    final next = c.copyWith(order: maxOrder + 1);
    return copyWith(columns: _reorderNormalize([...columns, next]));
  }

  ColumnsPrefs removeColumn(String id) {
    final out = columns.where((c) => c.id != id).toList();
    return copyWith(columns: _reorderNormalize(out));
  }

  static List<ColumnDef> _reorderNormalize(List<ColumnDef> list) {
    final sorted = [...list]..sort((a, b) => a.order.compareTo(b.order));
    var i = 0;
    return sorted.map((c) => c.copyWith(order: i++)).toList();
  }

  // ======= Validación para exportación =======

  /// Ajusta `imageColumnIndex` si está fuera de rango y verifica que haya
  /// consistencia entre lat/lng. Devuelve prefs corregidas + warnings.
  (ColumnsPrefs fixed, List<String> warnings) validateForExport() {
    final warnings = <String>[];

    // imageColumnIndex seguro
    final colsCount = columns.length;
    final img = imageColumnIndex.clamp(1, colsCount);
    if (img != imageColumnIndex) {
      warnings.add('imageColumnIndex fuera de rango. Se ajustó a $img.');
    }

    // lat/lng consistentes
    final hasLat = columns.any((c) => c.role == ColumnRole.latitude);
    final hasLng = columns.any((c) => c.role == ColumnRole.longitude);
    if (hasLat && !hasLng) {
      warnings.add('Hay Latitud sin Longitud. Considera añadir la columna de Longitud.');
    } else if (!hasLat && hasLng) {
      warnings.add('Hay Longitud sin Latitud. Considera añadir la columna de Latitud.');
    }

    return (copyWith(imageColumnIndex: img), warnings);
  }

  // ======= Igualdad =======

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ColumnsPrefs &&
        other.schemaVersion == schemaVersion &&
        other.imageColumnIndex == imageColumnIndex &&
        const DeepCollectionEquality().equals(other.columns, columns);
  }

  @override
  int get hashCode =>
      Object.hash(schemaVersion, imageColumnIndex, const DeepCollectionEquality().hash(columns));
}
