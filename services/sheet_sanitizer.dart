// lib/services/sheet_sanitizer.dart
//
// Carga y sanea una SheetData desde LocalStore SIN rehidratar basura de sesiones
// anteriores: ajusta columnas/filas, deduplica celdas/fotos, descarta paths
// inexistentes y sincroniza CrashGuard para que no "inyecte" nada viejo.

import 'dart:io';
import '../services/local_store.dart';      // SheetData / RowData
import '../services/crash_guard.dart';

class SheetSanitizerConfig {
  final int columns;
  final int rows;
  final int maxPhotosPerRow;
  final int maxPhotosTotal;

  const SheetSanitizerConfig({
    required this.columns,
    required this.rows,
    this.maxPhotosPerRow = 5,
    this.maxPhotosTotal = 5,
  });
}

class SheetSanitizer {
  const SheetSanitizer();

  /// Carga desde LocalStore y devuelve una SheetData *sanitizada*.
  /// Si no hay datos válidos, devuelve null (el caller arranca vacío).
  Future<SheetData?> loadClean({
    required String sheetId,
    required SheetSanitizerConfig cfg,
  }) async {
    // Aseguramos el "namespace" de sesión antes de tocar nada
    CrashGuard.I.setCurrentSheet(sheetId);

    final stored = await LocalStore.I.load(sheetId);
    if (stored == null || stored.sheetId != sheetId) {
      // Limpieza mínima de sesión
      CrashGuard.I.clearDraftForCurrentSheet();
      await CrashGuard.I.flushNow();
      return null;
    }

    // --- Headers normalizados ---
    final headers = List<String>.generate(cfg.columns, (i) {
      if (i < stored.headers.length) {
        final v = stored.headers[i];
        return v;
      }
      return '';
    });

    // --- Filas/celdas/fotos normalizadas ---
    final List<RowData> rows = <RowData>[];
    int totalPhotos = 0;

    for (var r = 0; r < cfg.rows; r++) {
      if (r < stored.rows.length) {
        final src = stored.rows[r];

        // Ajuste de celdas al ancho
        final cells = List<String>.generate(cfg.columns, (c) {
          if (c < src.cells.length) {
            final v = src.cells[c];
            return v;
          }
          return '';
        });

        // Fotos: dedupe, solo existentes, respetando límites
        final seen = <String>{};
        final List<String> photos = [];
        for (final any in src.photos) {
          final path = any;
          if (path.isEmpty || seen.contains(path)) continue;
          if (!File(path).existsSync()) continue;
          if (photos.length >= cfg.maxPhotosPerRow) break;
          if (totalPhotos >= cfg.maxPhotosTotal) break;
          photos.add(path);
          seen.add(path);
          totalPhotos++;
        }

        rows.add(RowData(
          cells: cells,
          photos: photos,
          lat: src.lat,
          lng: src.lng,
        ));
      } else {
        rows.add(RowData(cells: List.filled(cfg.columns, ''), photos: const []));
      }
    }

    final cleaned = SheetData(
      sheetId: sheetId,
      title: stored.title,
      headers: headers,
      rows: rows,
    );

    // --- Sincronización CrashGuard ---
    // 1) borradores efímeros de esta hoja
    CrashGuard.I.clearDraftForCurrentSheet();

    // 2) confirmar como "linkeadas" las fotos que *ya* están en la planilla
    final cg = CrashGuard.I.current();
    if (cg.photoPaths.isNotEmpty) {
      final present = <String>{for (final r in rows) ...r.photos};
      for (final p in List<String>.from(cg.photoPaths)) {
        if (present.contains(p)) {
          CrashGuard.I.confirmPhotoLinked(p);
        }
      }
    }

    // Persistimos el estado de sesión saneado
    await CrashGuard.I.flushNow();

    return cleaned;
  }
}
