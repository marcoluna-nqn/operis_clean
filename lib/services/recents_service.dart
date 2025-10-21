// lib/services/recents_service.dart
//
// Servicio robusto de "recientes" con:
// - Lectura/escritura segura (cola interna para evitar carreras)
// - Migración/validación de JSON dañados
// - Upsert ordenado y estable (favoritos arriba, luego fecha desc)
// - Preserva 'starred' al tocar/renombrar/duplicar
// - Límite suave de 200 entradas
//
// Formato guardado (SharedPreferences, key recents_v3):
// [
//   {"id": "...", "title": "...", "updatedAt": "ISO8601", "starred": true/false},
//   ...
// ]

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class RecentEntry {
  final String id;
  final String title;
  final DateTime updatedAt;
  final bool starred;

  const RecentEntry({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.starred,
  });

  RecentEntry copyWith({
    String? id,
    String? title,
    DateTime? updatedAt,
    bool? starred,
  }) {
    return RecentEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      starred: starred ?? this.starred,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
    'starred': starred,
  };

  static RecentEntry? fromJson(dynamic j) {
    if (j is! Map) return null;
    final map = Map<String, dynamic>.from(j);
    final id = (map['id'] ?? '').toString().trim();
    final title = (map['title'] ?? '').toString();
    final starred = (map['starred'] is bool) ? map['starred'] as bool : false;

    DateTime when;
    final rawDate = map['updatedAt'];
    if (rawDate is String) {
      when = DateTime.tryParse(rawDate) ?? DateTime.now();
    } else {
      when = DateTime.now();
    }

    if (id.isEmpty) return null;
    return RecentEntry(id: id, title: title, updatedAt: when, starred: starred);
  }
}

class RecentsService {
  RecentsService._();
  static final RecentsService I = RecentsService._();

  static const String _key = 'recents_v3';
  static const int _cap = 200;

  // Cola simple para serializar operaciones y evitar carreras entre awaits.
  Future<void> _queue = Future<void>.value();

  Future<T> _run<T>(Future<T> Function() job) {
    final c = _queue.then((_) => job());
    // Mantener la cola viva (aunque falle, que no corte la cadena)
    _queue = c.then((_) {}, onError: (_) {});
    return c;
  }

  // ---- API pública ----

  /// Agrega/actualiza una entrada y la coloca arriba.
  /// Preserva 'starred' si la entrada existe.
  Future<void> touch({required String id, required String title}) {
    return _run(() async {
      final list = await _read();
      final idx = list.indexWhere((e) => e.id == id);
      final prevStar = idx >= 0 ? list[idx].starred : false;

      // eliminar duplicados previos del mismo id
      if (idx >= 0) list.removeAt(idx);

      list.insert(
        0,
        RecentEntry(
          id: id,
          title: title,
          updatedAt: DateTime.now(),
          starred: prevStar,
        ),
      );

      _sortStable(list);
      await _write(list);
    });
  }

  /// Elimina una entrada por id (no falla si no existe).
  Future<void> remove(String id) {
    return _run(() async {
      final list = await _read();
      list.removeWhere((e) => e.id == id);
      await _write(list);
    });
  }

  /// Renombra preservando 'starred' y actualiza updatedAt.
  Future<void> rename({required String id, required String newTitle}) {
    return _run(() async {
      final list = await _read();
      final i = list.indexWhere((e) => e.id == id);
      if (i == -1) {
        // si no existe, créalo
        list.insert(
          0,
          RecentEntry(
            id: id,
            title: newTitle,
            updatedAt: DateTime.now(),
            starred: false,
          ),
        );
      } else {
        final e = list.removeAt(i);
        list.insert(
          0,
          e.copyWith(title: newTitle, updatedAt: DateTime.now()),
        );
      }
      _sortStable(list);
      await _write(list);
    });
  }

  /// Cambia el estado de favorito.
  Future<void> toggleStar(String id, {bool? value}) {
    return _run(() async {
      final list = await _read();
      final i = list.indexWhere((e) => e.id == id);
      if (i == -1) return;
      final e = list[i];
      final next = e.copyWith(starred: value ?? !e.starred);
      // Mover arriba si quedó favorito; si no, reordenar por fecha
      list
        ..removeAt(i)
        ..insert(0, next.copyWith(updatedAt: DateTime.now()));
      _sortStable(list);
      await _write(list);
    });
  }

  /// Devuelve la lista ordenada (favoritos arriba, luego fecha desc).
  Future<List<RecentEntry>> getAll() => _run(() async => await _read());

  /// Borra todo el listado (no toca archivos de planillas).
  Future<void> clear() {
    return _run(() async {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_key);
    });
  }

  // ---- Internos ----

  Future<List<RecentEntry>> _read() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_key);
      if (raw == null || raw.trim().isEmpty) return <RecentEntry>[];

      final decoded = jsonDecode(raw);
      if (decoded is! List) return <RecentEntry>[];

      // parseo tolerante
      final out = <RecentEntry>[];
      for (final e in decoded) {
        final item = RecentEntry.fromJson(e);
        if (item != null) out.add(item);
      }

      // dedupe por id manteniendo el más nuevo y preservando 'starred' si aplica
      final byId = <String, RecentEntry>{};
      for (final e in out) {
        final prev = byId[e.id];
        if (prev == null) {
          byId[e.id] = e;
        } else {
          // elegir el más reciente y OR de 'starred' para no perder favoritos
          final newer =
          e.updatedAt.isAfter(prev.updatedAt) ? e : prev;
          byId[e.id] = newer.copyWith(starred: e.starred || prev.starred);
        }
      }

      final list = byId.values.toList();
      _sortStable(list);
      // cap suave
      if (list.length > _cap) {
        return list.take(_cap).toList();
      }
      return list;
    } catch (_) {
      // corrupción: sanear
      return <RecentEntry>[];
    }
  }

  Future<void> _write(List<RecentEntry> list) async {
    try {
      _sortStable(list);
      // cap suave
      if (list.length > _cap) {
        list = list.take(_cap).toList();
      }
      final sp = await SharedPreferences.getInstance();
      final payload = jsonEncode(list.map((e) => e.toJson()).toList());
      await sp.setString(_key, payload);
    } catch (_) {
      // swallow: no romper la app por error de preferencia
    }
  }

  // favoritos primero, luego fecha desc (orden estable suficiente)
  void _sortStable(List<RecentEntry> list) {
    list.sort((a, b) {
      if (a.starred != b.starred) {
        return b.starred ? 1 : -1; // true primero
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }
}
