// lib/services/export_service.dart
import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:isolate';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image/image.dart' as im;

import 'export_xlsx_service.dart';
import 'pending_share_store.dart';
import 'net.dart';

typedef ProgressFn = void Function(double progress, String stage);
typedef ImagePreprocessor = FutureOr<List<int>?> Function(String imagePath);

class CancelToken { bool _c = false; bool get canceled => _c; void cancel() => _c = true; }

enum ExportAction { share, open, saveAs }

class ShareOutcome {
  ShareOutcome({
    required this.export,
    this.status,
    this.openedFallback = false,
    this.savedPath,
    this.csvFile,
  });
  final ExportResult export;
  final ShareResultStatus? status;
  final bool openedFallback;
  final String? savedPath;
  final XFile? csvFile;
  bool get shared => status == ShareResultStatus.success;
}

class ExportService {
  ExportService._();
  static final ExportService instance = ExportService._();

  /// Preprocesador “lite” para pasar directo a [run(imagePreprocessor: ...)].
  /// Redimensiona al lado mayor [maxDim] y comprime JPG a [quality].
  static ImagePreprocessor makeLitePreprocessor({int maxDim = 1600, int quality = 80}) {
    return (String path) => _preprocessLiteInIsolate(path, maxDim: maxDim, quality: quality);
  }

  Future<ShareOutcome> run({
    required ExportAction action,
    required List<String> headers,
    required List<List<String>> rows,
    Map<int, List<String>> imagesByRow = const {},
    int imageColumnIndex = 1,
    String sheetName = 'Planilla',

    // UX
    String? subject,
    String? message,
    String fileNameTemplate = r'{title}_{yyyy}{MM}{dd}_{HHmmss}',

    // Opcionales
    bool alsoShareCsv = false,
    String csvDelimiter = ',',
    bool csvUtf8Bom = true,
    ImagePreprocessor? imagePreprocessor,

    // Control
    CancelToken? cancel,
    ProgressFn? onProgress,
    Duration shareTimeout = const Duration(seconds: 25),
    int retries = 2,
  }) async {
    _tick(onProgress, 0.03, 'Preparando');

    final tempArtifacts = <String>[];

    try {
      // Preproc opcional de imágenes en Isolate (no muta originales).
      if (imagePreprocessor != null && imagesByRow.isNotEmpty) {
        final patched = <int, List<String>>{};
        int done = 0;
        final total = imagesByRow.values.fold<int>(0, (a, b) => a + b.length);
        for (final e in imagesByRow.entries) {
          _ensure(cancel);
          final list = <String>[];
          for (final path in e.value) {
            _ensure(cancel);
            final out = await imagePreprocessor(path);
            if (out == null) {
              list.add(path);
            } else {
              final tmp = await _tmpSibling(path);
              await File(tmp).writeAsBytes(out, flush: true);
              tempArtifacts.add(tmp);
              list.add(tmp);
            }
            done++;
            // avanza entre 0.03 y 0.20 mientras preprocesa
            final prog = 0.03 + (0.17 * (done / total.clamp(1, 1 << 20)));
            _tick(onProgress, prog, 'Procesando fotos');
          }
          patched[e.key] = list;
        }
        imagesByRow = patched;
      }

      _tick(onProgress, 0.25, 'Generando XLSX');

      // Export sin bloquear UI. Mantengo en main isolate por compatibilidad.
      // (El peso grande ya se redujo en el paso anterior).
      final export = await _retry<ExportResult>(
            () => ExportXlsxService.instance.exportToXlsx(
          headers: headers,
          rows: rows,
          imagesByRow: imagesByRow,
          imageColumnIndex: imageColumnIndex.clamp(1, headers.length + 1),
          sheetName: sheetName,
        ),
        retries: retries,
      );

      _tick(onProgress, 0.65, 'Archivo listo');

      // CSV opcional
      XFile? csv;
      if (alsoShareCsv) {
        final csvX = await _buildCsvTemp(
          baseName: _fileBase(_renderName(fileNameTemplate, sheetName)),
          headers: headers,
          rows: rows,
          delimiter: csvDelimiter,
          withBom: csvUtf8Bom,
        );
        csv = csvX;
        tempArtifacts.add(csvX.path);
      }

      final baseName = _fileBase(_renderName(fileNameTemplate, sheetName));
      final xlsxName = '$baseName.xlsx';
      final subjectFinal = subject ?? '$sheetName – Excel';

      switch (action) {
        case ExportAction.share:
          try {
            final res = await _retry<ShareResult>(
                  () => SharePlus.instance
                  .share(
                ShareParams(
                  files: [if (csv != null) csv, export.shareXFile],
                  subject: subjectFinal,
                  text: message ?? 'Abrir el XLSX en Excel/Numbers.',
                ),
              )
                  .timeout(shareTimeout),
              retries: retries,
            );
            _tick(onProgress, 1.0, 'Compartido');
            return ShareOutcome(export: export, status: res.status, csvFile: csv);
          } catch (_) {
            if (!await Net.I.isOnline()) {
              await PendingShareStore.I.enqueueFiles(
                [if (csv != null) csv, export.shareXFile],
                subject: subjectFinal,
                text: message ?? 'Se enviará automáticamente al volver a tener conexión.',
              );
              _tick(onProgress, 1.0, 'En cola offline');
              return ShareOutcome(export: export, status: ShareResultStatus.dismissed, csvFile: csv);
            }
            // Fallback: abrir
            try {
              await OpenFilex.open(Platform.isAndroid ? export.shareXFile.path : export.xlsxFile.path);
              _tick(onProgress, 1.0, 'Abierto');
              return ShareOutcome(export: export, openedFallback: true, csvFile: csv);
            } catch (_) {
              _tick(onProgress, 1.0, 'Error');
              rethrow;
            }
          }

        case ExportAction.open:
          _ensure(cancel);
          await OpenFilex.open(Platform.isAndroid ? export.shareXFile.path : export.xlsxFile.path);
          _tick(onProgress, 1.0, 'Abierto');
          return ShareOutcome(export: export, openedFallback: true, csvFile: csv);

        case ExportAction.saveAs:
          _ensure(cancel);
          final loc = await fs.getSaveLocation(suggestedName: xlsxName);
          if (loc == null || loc.path.isEmpty) {
            _tick(onProgress, 1.0, 'Cancelado');
            return ShareOutcome(export: export, status: ShareResultStatus.dismissed, csvFile: csv);
          }
          var dest = loc.path;
          if (!dest.toLowerCase().endsWith('.xlsx')) dest = '$dest.xlsx';
          await File(export.xlsxFile.path).copy(dest);
          if (csv != null) {
            final csvLoc = p.setExtension(dest, '.csv');
            await File(csv.path).copy(csvLoc);
          }
          _tick(onProgress, 1.0, 'Guardado');
          return ShareOutcome(export: export, savedPath: dest, csvFile: csv);
      }
    } finally {
      for (final t in tempArtifacts) {
        try { await File(t).delete(); } catch (_) {}
      }
    }
  }

  // ----------------- helpers -----------------

  Future<T> _retry<T>(Future<T> Function() task, {int retries = 1}) async {
    int attempts = 0;
    while (true) {
      try {
        return await task();
      } catch (_) {
        if (attempts++ >= retries) rethrow;
        await Future.delayed(Duration(milliseconds: 250 * attempts));
      }
    }
  }

  void _tick(ProgressFn? fn, double p, String stage) => fn?.call(p.clamp(0, 1), stage);
  void _ensure(CancelToken? t) { if (t?.canceled == true) throw _Canceled(); }

  Future<XFile> _buildCsvTemp({
    required String baseName,
    required List<String> headers,
    required List<List<String>> rows,
    String delimiter = ',',
    bool withBom = true,
  }) async {
    final sb = StringBuffer();

    String esc(String v) {
      final needs = v.contains(delimiter) || v.contains('"') || v.contains('\n') || v.contains('\r');
      final w = v.replaceAll('"', '""');
      return needs ? '"$w"' : w;
    }

    sb.writeAll(headers.map(esc), delimiter);
    sb.write('\r\n');

    for (final r in rows) {
      sb.writeAll(r.map(esc), delimiter);
      sb.write('\r\n');
    }

    final bytes = withBom
        ? Uint8List.fromList(const [0xEF, 0xBB, 0xBF] + utf8.encode(sb.toString()))
        : Uint8List.fromList(utf8.encode(sb.toString()));

    final tmpDir = await getTemporaryDirectory();
    final path = p.join(tmpDir.path, '$baseName.csv');
    final f = File(path)..writeAsBytesSync(bytes, flush: true);
    return XFile(f.path, mimeType: 'text/csv', name: p.basename(f.path));
  }

  String _renderName(String tpl, String title) {
    final now = DateTime.now();
    final m = {
      'title': _fileBase(title.isEmpty ? 'Bitacora' : title),
      'yyyy': DateFormat('yyyy').format(now),
      'MM': DateFormat('MM').format(now),
      'dd': DateFormat('dd').format(now),
      'HHmmss': DateFormat('HHmmss').format(now),
    };
    return tpl.replaceAllMapped(RegExp(r'\{([a-zA-Z]+)\}'), (x) => m[x[1]] ?? '');
  }

  String _fileBase(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(RegExp(r'\s+'), '_').trim();

  Future<String> _tmpSibling(String sourcePath) async {
    final dir = File(sourcePath).parent;
    final name = 'tmp_${DateTime.now().microsecondsSinceEpoch}.jpg';
    return p.join(dir.path, name);
  }
}

class _Canceled implements Exception {}

/// --- Trabajo pesado en segundo plano ---

Future<List<int>?> _preprocessLiteInIsolate(String path, {required int maxDim, required int quality}) {
  // Usa Isolate.run. Captura solo tipos enviables (String/int).
  return Isolate.run(() async {
    try {
      final bytes = await File(path).readAsBytes();
      var img = im.decodeImage(bytes);
      if (img == null) return null;

      final w = img.width;
      final h = img.height;
      final maxSide = w > h ? w : h;

      if (maxSide > maxDim) {
        img = im.copyResize(
          img,
          width: w >= h ? maxDim : null,
          height: h > w ? maxDim : null,
          interpolation: im.Interpolation.average,
        );
      }
      final out = im.encodeJpg(img, quality: quality);
      return Uint8List.fromList(out);
    } catch (_) {
      return null;
    }
  });
}
