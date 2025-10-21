// lib/models/sheet_session_state.dart
import 'dart:convert' show jsonDecode, jsonEncode, utf8;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

/// Estado de una foto asociada a la hoja.
enum PhotoStatus { pending, persisted, failed }

@immutable
class PendingPhoto {
  final String id;              // clave estable (p.ej., uuid)
  final String localPath;       // ruta local del archivo (solo cliente)
  final PhotoStatus status;     // estado de persistencia
  final DateTime addedAt;       // cuándo se adjuntó
  final int? widthPx;
  final int? heightPx;
  final int? fileBytes;         // tamaño en bytes (opcional)

  const PendingPhoto({
    required this.id,
    required this.localPath,
    required this.status,
    required this.addedAt,
    this.widthPx,
    this.heightPx,
    this.fileBytes,
  });

  PendingPhoto copyWith({
    String? id,
    String? localPath,
    PhotoStatus? status,
    DateTime? addedAt,
    int? widthPx,
    int? heightPx,
    int? fileBytes,
  }) {
    return PendingPhoto(
      id: id ?? this.id,
      localPath: localPath ?? this.localPath,
      status: status ?? this.status,
      addedAt: addedAt ?? this.addedAt,
      widthPx: widthPx ?? this.widthPx,
      heightPx: heightPx ?? this.heightPx,
      fileBytes: fileBytes ?? this.fileBytes,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'localPath': localPath,
    'status': status.name,
    'addedAt': addedAt.toIso8601String(),
    if (widthPx != null) 'widthPx': widthPx,
    if (heightPx != null) 'heightPx': heightPx,
    if (fileBytes != null) 'fileBytes': fileBytes,
  };

  factory PendingPhoto.fromJson(Map<String, dynamic> j) {
    // Migración de booleano "persisted" → enum
    PhotoStatus status;
    if (j['status'] is String) {
      final s = (j['status'] as String).toLowerCase();
      status = PhotoStatus.values.firstWhere(
            (e) => e.name == s,
        orElse: () => PhotoStatus.pending,
      );
    } else if (j['persisted'] is bool) {
      status = (j['persisted'] as bool) ? PhotoStatus.persisted : PhotoStatus.pending;
    } else {
      status = PhotoStatus.pending;
    }

    return PendingPhoto(
      id: (j['id'] ?? '').toString(),
      localPath: (j['localPath'] ?? '').toString(),
      status: status,
      addedAt: DateTime.tryParse((j['addedAt'] ?? '').toString()) ?? DateTime.now(),
      widthPx: (j['widthPx'] as num?)?.toInt(),
      heightPx: (j['heightPx'] as num?)?.toInt(),
      fileBytes: (j['fileBytes'] as num?)?.toInt(),
    );
  }

  // --------- igualdad / hashing para colecciones de objetos ----------
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PendingPhoto &&
        other.id == id &&
        other.localPath == localPath &&
        other.status == status &&
        other.addedAt.isAtSameMomentAs(addedAt) &&
        other.widthPx == widthPx &&
        other.heightPx == heightPx &&
        other.fileBytes == fileBytes;
  }

  @override
  int get hashCode => Object.hash(
    id,
    localPath,
    status,
    addedAt.millisecondsSinceEpoch,
    widthPx,
    heightPx,
    fileBytes,
  );
}

/// Snapshot serializable del estado de edición de una hoja.
@immutable
class SheetSessionState {
  /// Versión de esquema del snapshot.
  static const int schemaVersion = 2;

  final String sheetId;
  final String draft;              // texto del borrador
  final double scrollOffset;       // px
  final List<PendingPhoto> photos; // inmutable y ordenada
  final DateTime updatedAt;        // última actualización

  const SheetSessionState._({
    required this.sheetId,
    required this.draft,
    required this.scrollOffset,
    required this.photos,
    required this.updatedAt,
  });

  /// Constructor público que garantiza inmutabilidad y orden determinista.
  factory SheetSessionState({
    required String sheetId,
    String draft = '',
    double scrollOffset = 0,
    List<PendingPhoto> photos = const <PendingPhoto>[],
    DateTime? updatedAt,
  }) {
    final safeScroll = (scrollOffset.isFinite && scrollOffset >= 0) ? scrollOffset : 0.0;
    final sorted = List<PendingPhoto>.from(photos)
      ..sort((a, b) {
        final byAdded = a.addedAt.compareTo(b.addedAt);
        if (byAdded != 0) return byAdded;
        return a.id.compareTo(b.id);
      });
    return SheetSessionState._(
      sheetId: sheetId,
      draft: draft,
      scrollOffset: safeScroll,
      photos: List<PendingPhoto>.unmodifiable(sorted),
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  factory SheetSessionState.initial(String sheetId) => SheetSessionState(sheetId: sheetId);

  SheetSessionState copyWith({
    String? sheetId,
    String? draft,
    double? scrollOffset,
    List<PendingPhoto>? photos,
    DateTime? updatedAt,
  }) {
    return SheetSessionState(
      sheetId: sheetId ?? this.sheetId,
      draft: draft ?? this.draft,
      scrollOffset: scrollOffset ?? this.scrollOffset,
      photos: photos ?? this.photos,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  // ----------------- Serialización / Migración -----------------

  Map<String, dynamic> toJson() => {
    'v': schemaVersion,
    'sheetId': sheetId,
    'draft': draft,
    'scrollOffset': scrollOffset,
    'updatedAt': updatedAt.toIso8601String(),
    'photos': photos.map((p) => p.toJson()).toList(),
  };

  /// Versión redactada para logs/telemetría (oculta rutas locales).
  Map<String, dynamic> toRedactedJson() => {
    'v': schemaVersion,
    'sheetId': sheetId,
    'draftLen': draft.length,
    'scrollOffset': scrollOffset,
    'updatedAt': updatedAt.toIso8601String(),
    'photos': photos
        .map((p) => {
      'id': p.id,
      'status': p.status.name,
      'addedAt': p.addedAt.toIso8601String(),
      if (p.widthPx != null) 'widthPx': p.widthPx,
      if (p.heightPx != null) 'heightPx': p.heightPx,
      if (p.fileBytes != null) 'fileBytes': p.fileBytes,
      'localPath': 'redacted',
    })
        .toList(),
  };

  Uint8List toBytes() => utf8.encode(jsonEncode(toJson()));

  static SheetSessionState fromBytes(Uint8List bytes) {
    final j = jsonDecode(utf8.decode(bytes));
    return SheetSessionState.fromJson(Map<String, dynamic>.from(j as Map));
  }

  static SheetSessionState fromJson(Map<String, dynamic> j) {
    final m = _migrate(j);
    final photos = (m['photos'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => PendingPhoto.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    return SheetSessionState(
      sheetId: (m['sheetId'] ?? '').toString(),
      draft: (m['draft'] ?? '').toString(),
      scrollOffset: (m['scrollOffset'] as num?)?.toDouble() ?? 0.0,
      photos: photos,
      updatedAt: DateTime.tryParse((m['updatedAt'] ?? '').toString()) ?? DateTime.now(),
    );
  }

  /// Migra snapshots antiguos a `schemaVersion`.
  static Map<String, dynamic> _migrate(Map<String, dynamic> raw) {
    final v = (raw['v'] as num?)?.toInt() ?? 0;
    final j = Map<String, dynamic>.from(raw);

    // v0 → v1: podía no tener 'v', fotos con {id, localPath, persisted: bool}
    if (v < 1) {
      final photos = (j['photos'] as List? ?? const [])
          .whereType<Map>()
          .map((e) {
        final map = Map<String, dynamic>.from(e);
        if (!map.containsKey('status') && map.containsKey('persisted')) {
          final persisted = map['persisted'] == true;
          map['status'] = persisted ? 'persisted' : 'pending';
        }
        map['addedAt'] ??= DateTime.now().toIso8601String();
        return map;
      })
          .toList();
      j['photos'] = photos;
      j['v'] = 1;
    }

    // v1 → v2: asegurar tipos válidos y scrollOffset >= 0
    if ((j['v'] as int) < 2) {
      final so = (j['scrollOffset'] as num?)?.toDouble() ?? 0.0;
      j['scrollOffset'] = (so.isFinite && so >= 0) ? so : 0.0;
      j['v'] = 2;
    }

    return j;
  }

  // ----------------- Helpers de dominio -----------------

  bool get isEmpty => draft.isEmpty && photos.isEmpty;

  int indexOfPhoto(String id) => photos.indexWhere((p) => p.id == id);

  PendingPhoto? photoById(String id) => photos.firstWhereOrNull((p) => p.id == id);

  SheetSessionState upsertPhoto(PendingPhoto p) {
    final i = indexOfPhoto(p.id);
    final list = List<PendingPhoto>.from(photos);
    if (i == -1) {
      list.add(p);
    } else {
      list[i] = p;
    }
    list.sort((a, b) {
      final byAdded = a.addedAt.compareTo(b.addedAt);
      if (byAdded != 0) return byAdded;
      return a.id.compareTo(b.id);
    });
    return copyWith(photos: List<PendingPhoto>.unmodifiable(list));
  }

  SheetSessionState removePhoto(String id) {
    final list = photos.where((p) => p.id != id).toList();
    return copyWith(photos: List<PendingPhoto>.unmodifiable(list));
  }

  SheetSessionState limitPhotos(int max) {
    if (photos.length <= max) return this;
    final list = List<PendingPhoto>.from(photos)
      ..sort((a, b) => a.addedAt.compareTo(b.addedAt)); // más viejas primero
    final trimmed = list.sublist(list.length - max);
    return copyWith(photos: List<PendingPhoto>.unmodifiable(trimmed));
  }

  SheetSessionState withDraft(String newDraft) => copyWith(draft: newDraft);

  SheetSessionState withScroll(double offset) {
    final v = (offset.isFinite && offset >= 0) ? offset : 0.0;
    return copyWith(scrollOffset: v);
  }

  /// Firma "estable" para detectar no-ops (excluye campos volátiles).
  /// No incluye `updatedAt` ni `addedAt` de fotos.
  String coreSignature() {
    final sig = {
      'sheetId': sheetId,
      'draft': draft,
      // Redondeo reduce ruido por subpíxeles
      'scroll': double.parse(scrollOffset.toStringAsFixed(2)),
      'photos': photos
          .map((p) => {
        'id': p.id,
        'status': p.status.name,
      })
          .toList(),
    };
    return jsonEncode(sig);
  }

  /// Valida el estado y devuelve una lista de advertencias (si las hay).
  List<String> validate() {
    final warnings = <String>[];

    if (sheetId.trim().isEmpty) {
      warnings.add('sheetId vacío');
    }
    if (!(scrollOffset.isFinite && scrollOffset >= 0)) {
      warnings.add('scrollOffset inválido');
    }
    // ids duplicados
    final seen = <String>{};
    final dups = <String>[];
    for (final p in photos) {
      if (p.id.trim().isEmpty) warnings.add('foto con id vacío');
      if (!seen.add(p.id)) dups.add(p.id);
      if (p.localPath.trim().isEmpty) warnings.add('foto ${p.id} sin localPath');
    }
    if (dups.isNotEmpty) {
      warnings.add('ids de foto duplicados: ${dups.toSet().join(', ')}');
    }
    return warnings;
  }

  // ----------------- Igualdad / hashing -----------------

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SheetSessionState &&
        other.sheetId == sheetId &&
        other.draft == draft &&
        other.scrollOffset == scrollOffset &&
        const DeepCollectionEquality().equals(other.photos, photos);
    // NOTA: exclude updatedAt para favorecer no-ops
  }

  @override
  int get hashCode => Object.hash(
    sheetId,
    draft,
    scrollOffset.toStringAsFixed(2),
    const DeepCollectionEquality().hash(photos),
  );

  @override
  String toString() =>
      'SheetSessionState(sheetId=$sheetId, draftLen=${draft.length}, '
          'scroll=${scrollOffset.toStringAsFixed(1)}, photos=${photos.length})';
}
