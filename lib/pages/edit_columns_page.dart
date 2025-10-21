// lib/services/columns_prefs.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rol semántico de una columna para mejorar exportación/UX.
enum ColumnRole { normal, latitude, longitude }

extension ColumnRoleX on ColumnRole {
  String get label {
    switch (this) {
      case ColumnRole.normal:
        return 'Normal';
      case ColumnRole.latitude:
        return 'Latitud';
      case ColumnRole.longitude:
        return 'Longitud';
    }
  }

  static ColumnRole fromString(String? v) {
    switch (v) {
      case 'latitude':
        return ColumnRole.latitude;
      case 'longitude':
        return ColumnRole.longitude;
      default:
        return ColumnRole.normal;
    }
  }

  String get asString {
    switch (this) {
      case ColumnRole.latitude:
        return 'latitude';
      case ColumnRole.longitude:
        return 'longitude';
      case ColumnRole.normal:
        return 'normal';
    }
  }
}

/// Definición de una columna configurable por el usuario.
class ColumnSpec {
  final String key; // estable, usado como id
  String label; // visible
  bool enabled;
  ColumnRole role;

  ColumnSpec({
    required this.key,
    required this.label,
    this.enabled = true,
    this.role = ColumnRole.normal,
  });

  factory ColumnSpec.fromJson(Map<String, dynamic> j) => ColumnSpec(
    key: j['key'] as String,
    label: j['label'] as String? ?? 'Columna',
    enabled: j['enabled'] as bool? ?? true,
    role: ColumnRoleX.fromString(j['role'] as String?),
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'enabled': enabled,
    'role': role.asString,
  };

  ColumnSpec copy() =>
      ColumnSpec(key: key, label: label, enabled: enabled, role: role);
}

/// Preferencias completas para exportación y columnas.
class ColumnsPrefs {
  List<ColumnSpec> columns;
  bool includePhotosSheet;
  bool insertThumbnail;
  int thumbnailColumnIndex; // 1-based

  ColumnsPrefs({
    required this.columns,
    this.includePhotosSheet = true,
    this.insertThumbnail = false,
    this.thumbnailColumnIndex = 1,
  });

  factory ColumnsPrefs.defaults() => ColumnsPrefs(
    columns: List<ColumnSpec>.generate(
      5,
          (i) => ColumnSpec(
        key: 'c${i + 1}',
        label: 'Col ${i + 1}',
      ),
    ),
    includePhotosSheet: true,
    insertThumbnail: false,
    thumbnailColumnIndex: 1,
  );

  factory ColumnsPrefs.fromJson(Map<String, dynamic> j) {
    final cols = (j['columns'] as List<dynamic>? ?? [])
        .map((e) => ColumnSpec.fromJson(e as Map<String, dynamic>))
        .toList();
    return ColumnsPrefs(
      columns: cols.isEmpty ? ColumnsPrefs.defaults().columns : cols,
      includePhotosSheet: j['includePhotosSheet'] as bool? ?? true,
      insertThumbnail: j['insertThumbnail'] as bool? ?? false,
      thumbnailColumnIndex: j['thumbnailColumnIndex'] as int? ?? 1,
    )._clampThumb();
  }

  Map<String, dynamic> toJson() => {
    'columns': columns.map((c) => c.toJson()).toList(),
    'includePhotosSheet': includePhotosSheet,
    'insertThumbnail': insertThumbnail,
    'thumbnailColumnIndex': thumbnailColumnIndex,
  };

  ColumnsPrefs _clampThumb() {
    if (columns.isEmpty) {
      thumbnailColumnIndex = 1;
    } else {
      thumbnailColumnIndex = thumbnailColumnIndex.clamp(1, columns.length);
    }
    return this;
  }
}

/// Controller con persistencia y debounce.
class ColumnsPrefsController extends ChangeNotifier {
  static const _kKey = 'columns_prefs_v1';
  final Duration _debounce = const Duration(milliseconds: 400);

  ColumnsPrefs prefs = ColumnsPrefs.defaults();
  bool isDirty = false;
  bool isSaving = false;

  Timer? _t;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kKey);
    if (raw == null || raw.isEmpty) {
      prefs = ColumnsPrefs.defaults();
      return;
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      prefs = ColumnsPrefs.fromJson(map);
    } catch (_) {
      prefs = ColumnsPrefs.defaults();
    }
  }

  Future<void> _saveNow() async {
    isSaving = true;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kKey, jsonEncode(prefs.toJson()));
      isDirty = false;
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  void _markDirtyAndScheduleSave() {
    isDirty = true;
    _t?.cancel();
    _t = Timer(_debounce, _saveNow);
    notifyListeners();
  }

  // ==== Mutadores de columnas ====

  void addColumn(String label) {
    final id = _uniqueKeyFrom(label);
    prefs.columns.add(ColumnSpec(key: id, label: label));
    prefs._clampThumb();
    _markDirtyAndScheduleSave();
  }

  void rename(String key, String newLabel) {
    final c = _byKey(key);
    if (c == null) return;
    c.label = newLabel;
    _markDirtyAndScheduleSave();
  }

  void setEnabled(String key, bool v) {
    final c = _byKey(key);
    if (c == null) return;
    c.enabled = v;
    _markDirtyAndScheduleSave();
  }

  void setRole(String key, ColumnRole role) {
    final c = _byKey(key);
    if (c == null) return;
    c.role = role;
    _markDirtyAndScheduleSave();
  }

  void removeByKey(String key) {
    prefs.columns.removeWhere((c) => c.key == key);
    prefs._clampThumb();
    _markDirtyAndScheduleSave();
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    final item = prefs.columns.removeAt(oldIndex);
    prefs.columns.insert(newIndex, item);
    _markDirtyAndScheduleSave();
  }

  // ==== Mutadores de exportación ====

  void setIncludePhotosSheet(bool v) {
    prefs.includePhotosSheet = v;
    _markDirtyAndScheduleSave();
  }

  void setInsertThumbnail(bool v) {
    prefs.insertThumbnail = v;
    _markDirtyAndScheduleSave();
  }

  void setThumbnailColumnIndex(int oneBased) {
    prefs.thumbnailColumnIndex =
        oneBased.clamp(1, prefs.columns.length);
    _markDirtyAndScheduleSave();
  }

  // ==== Import/Reset ====

  void importFromMap(Map<String, dynamic> map) {
    prefs = ColumnsPrefs.fromJson(map);
    _markDirtyAndScheduleSave();
  }

  void resetDefaults() {
    prefs = ColumnsPrefs.defaults();
    _markDirtyAndScheduleSave();
  }

  // ==== Util ====

  ColumnSpec? _byKey(String key) {
    try {
      return prefs.columns.firstWhere((c) => c.key == key);
    } catch (_) {
      return null;
    }
  }

  String _uniqueKeyFrom(String label) {
    final base = 'c_${label.toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp('_+'), '_')
        .trim()}';
    final ts = DateTime.now().microsecondsSinceEpoch;
    return base.isEmpty ? 'c$ts' : '${base}_$ts';
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }
}
