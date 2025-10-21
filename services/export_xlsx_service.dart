// lib/services/export_xlsx_service.dart
// XLSX real, autoFit, miniaturas y hoja "Fotos". Offline. Android + Windows.
// Escritura atómica en Documentos\Bitacora\exports (Win) o AppDocs/Bitacora/exports (Android).
// Copia en Temp para compartir. Helpers para abrir archivo/carpeta.
// Sin TODOs, null-safety, sin dependencias experimentales.

import 'dart:io';
import 'dart:typed_data';

// XFile
import 'package:file_selector/file_selector.dart' as fs;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xls;

class ExportCancelToken {
  bool _c = false;
  bool get canceled => _c;
  void cancel() => _c = true;
}

class ExportResult {
  final File xlsxFile;     // Archivo final persistente
  final XFile shareXFile;  // Copia en Temp para SharePlus
  final List<String> warnings;
  const ExportResult({
    required this.xlsxFile,
    required this.shareXFile,
    this.warnings = const <String>[],
  });
}

class ExportXlsxService {
  ExportXlsxService._();
  static final ExportXlsxService instance = ExportXlsxService._();

  Future<ExportResult> exportToXlsx({
    required List<String> headers,
    required List<List<String>> rows,
    required Map<int, List<String>> imagesByRow,
    required int imageColumnIndex, // 1-based
    required String sheetName,
    bool includePhotosSheet = true,
    ExportCancelToken? cancelToken,
    void Function(double progress, String stage)? onProgress,
  }) async {
    final warnings = <String>[];
    void step(double v, String s) => onProgress?.call(v.clamp(0.0, 1.0), s);
    void ensure() {
      if (cancelToken?.canceled == true) {
        throw const FileSystemException('Exportación cancelada');
      }
    }

    ensure();
    final safeTitle = _sheetName(sheetName.isEmpty ? 'Bitacora' : sheetName);

    // Rutas
    step(0.02, 'Preparando carpetas');
    final exportDir = await _ensureExportDir();
    final tmpDir = await getTemporaryDirectory();
    final stamp = _ts();
    final base = _fileBase(safeTitle);
    final outPath = p.join(exportDir.path, '${base}_$stamp.xlsx');
    final cachePath = p.join(tmpDir.path, '${base}_$stamp.xlsx');

    // Libro
    step(0.06, 'Creando libro');
    final wb = xls.Workbook();
    try {
      final ws = wb.worksheets[0];
      ws.name = safeTitle.length <= 31 ? safeTitle : safeTitle.substring(0, 31);

      xls.Worksheet? fotosWs;
      if (includePhotosSheet) {
        fotosWs = wb.worksheets.addWithName('Fotos');
      }

      // Estilos
      final hdr = wb.styles.add('hdr')
        ..bold = true
        ..hAlign = xls.HAlignType.center
        ..vAlign = xls.VAlignType.center
        ..backColor = '#EFEFEF';
      final body = wb.styles.add('body')
        ..hAlign = xls.HAlignType.left
        ..vAlign = xls.VAlignType.center;

      // Headers base seguros. Si no vienen, generamos 5 columnas por defecto.
      final baseHeaders = headers.isNotEmpty
          ? List<String>.from(headers)
          : List<String>.generate(5, (i) => 'Col ${i + 1}');

      // Agregar columna "Fotos" si no existe
      final hasFotosHeader =
      baseHeaders.any((h) => h.trim().toLowerCase() == 'fotos');
      final extendedHeaders =
      hasFotosHeader ? List<String>.from(baseHeaders) : [...baseHeaders, 'Fotos'];

      // Escribir encabezados
      for (var c = 0; c < extendedHeaders.length; c++) {
        final cell = ws.getRangeByIndex(1, c + 1);
        cell.setText(_sanitizeText(extendedHeaders[c]));
        cell.cellStyle = hdr;
      }
      ws.getRangeByIndex(1, 1, 1, extendedHeaders.length).rowHeight = 24;

      final dataCols = extendedHeaders.length;
      final imgCol = imageColumnIndex.clamp(1, dataCols);
      final fotosLinkCol = hasFotosHeader ? null : dataCols;
      final latIdx = _findHeader(baseHeaders, const ['lat', 'latitud', 'latitude']);
      final lngIdx = _findHeader(baseHeaders, const ['lng', 'lon', 'longitud', 'longitude']);

      // Hoja Fotos
      final anchorBySrcRow = <int, int>{};
      if (includePhotosSheet && fotosWs != null) {
        step(0.12, 'Insertando fotos');
        _fillFotosSheetGrouped(
          wb: wb,
          fotos: fotosWs,
          headers: baseHeaders,
          rows: rows,
          imagesByRow: imagesByRow,
          latIdx: latIdx,
          lngIdx: lngIdx,
          warnings: warnings,
          anchorBySrcRow: anchorBySrcRow,
          cancelToken: cancelToken,
          onProgress: (ratio) => step(0.12 + ratio * 0.24, 'Insertando fotos'),
        );
      }

      // Datos
      step(0.40, 'Escribiendo datos');
      const thumbPx = 112;

      if (rows.isEmpty) {
        // Al menos una fila para evitar XLSX “vacío”.
        final excelRow = 2;
        ws.getRangeByIndex(excelRow, 1).setText('Sin datos');
        ws.getRangeByIndex(excelRow, 1).cellStyle = body;
      } else {
        final totalRows = rows.length;
        for (var r = 0; r < rows.length; r++) {
          ensure();
          final excelRow = r + 2;
          final vals = rows[r];

          // Escribir celdas base
          for (var c = 0; c < baseHeaders.length; c++) {
            final cell = ws.getRangeByIndex(excelRow, c + 1);
            final value = c < vals.length ? vals[c] : '';
            _setTypedFromString(cell, value);
            cell.cellStyle = body;
          }

          // Link a mapa si hay lat/lng
          final (lat, lng) = _extractLatLng(vals, latIdx, lngIdx);
          if (lat != null && lng != null) {
            final linkCol = (latIdx != -1 ? latIdx : 0) + 1;
            _writeMapLink(ws, excelRow, linkCol, lat, lng);
          }

          // Miniatura + link a hoja Fotos
          final pics = imagesByRow[r] ?? const <String>[];
          if (pics.isNotEmpty) {
            _insertThumbnail(
              ws,
              row1Based: excelRow,
              col1Based: imgCol,
              firstPath: pics.first,
              thumbPx: thumbPx,
              warnings: warnings,
            );
            final anchor = anchorBySrcRow[r];
            if (anchor != null) {
              ws.hyperlinks.add(
                ws.getRangeByIndex(excelRow, imgCol),
                xls.HyperlinkType.workbook,
                'Fotos!B$anchor',
              );
            }
            if (fotosLinkCol != null) {
              final cell = ws.getRangeByIndex(excelRow, fotosLinkCol);
              cell.setText('Fotos (${pics.length})');
              if (anchor != null) {
                ws.hyperlinks.add(cell, xls.HyperlinkType.workbook, 'Fotos!B$anchor');
              }
            }
          }

          if (r % 8 == 0) {
            final baseProg = 0.40 + (0.30 * (r / totalRows));
            step(baseProg, 'Escribiendo datos');
          }
        }
      }

      // AutoFit, bordes, filtro y freeze
      final lastRow = rows.isEmpty ? 2 : rows.length + 1;

      // AutoFit sobre el rango usado por columna, excluye columna de miniaturas
      for (var c = 1; c <= dataCols; c++) {
        if (c == imgCol) continue;
        ws.getRangeByIndex(1, c, lastRow, c).autoFitColumns();
      }

      // anchura fija para la columna de foto
      _setPictureColumnWidth(ws, imgCol, thumbPx: thumbPx);

      final used = ws.getRangeByIndex(1, 1, lastRow, dataCols);
      used.cellStyle.borders.all
        ..lineStyle = xls.LineStyle.thin
        ..color = '#DDDDDD';
      ws.autoFilters.filterRange = used;

      // freeze panes: Range.freezePanes()
      ws.getRangeByIndex(2, 1).freezePanes();

      // Guardado atómico + copia en Temp
      step(0.86, 'Guardando');
      final bytes = wb.saveAsStream();

      final outTmp = File(p.join(exportDir.path, '.${p.basename(outPath)}.part'));
      await outTmp.writeAsBytes(bytes, flush: true);
      if (await File(outPath).exists()) {
        try { await File(outPath).delete(); } catch (_) {}
      }
      await outTmp.rename(outPath);

      final cacheCopy = File(cachePath);
      await cacheCopy.writeAsBytes(bytes, flush: true);

      step(1.0, 'OK');

      return ExportResult(
        xlsxFile: File(outPath),
        shareXFile: XFile(
          cacheCopy.path,
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          name: p.basename(cacheCopy.path),
        ),
        warnings: warnings,
      );
    } finally {
      wb.dispose(); // libera siempre
    }
  }

  // ===== Entrega local rápida =====

  Future<void> openFile(File f) async {
    await OpenFilex.open(f.path);
  }

  Future<void> revealInFolder(File f) async {
    if (Platform.isWindows) {
      try {
        await Process.run('explorer.exe', ['/select,', f.path]);
      } catch (_) {
        await OpenFilex.open(p.dirname(f.path));
      }
    } else {
      await OpenFilex.open(p.dirname(f.path));
    }
  }

  /// “Guardar como…” compatible con file_selector antiguos: usa getDirectoryPath.
  Future<File?> saveAsCopy(File source, {String? suggestedName}) async {
    final dirPath = await fs.getDirectoryPath(confirmButtonText: 'Seleccionar');
    if (dirPath == null) return null;
    final dest = File(p.join(dirPath, suggestedName ?? p.basename(source.path)));
    await dest.writeAsBytes(await source.readAsBytes(), flush: true);
    return dest;
  }

  Future<void> shareQuick(XFile xf, {File? fallbackReveal}) async {
    try {
      final f = File(xf.path);
      if (!await f.exists() || await f.length() == 0) return; // evita “solo texto”
      await Share.shareXFiles([xf], text: 'Archivo XLSX generado con Bitácora');
    } catch (_) {
      if (fallbackReveal != null) {
        await revealInFolder(fallbackReveal);
      }
    }
  }

  // ===== Hoja “Fotos” agrupada por fila =====
  void _fillFotosSheetGrouped({
    required xls.Workbook wb,
    required xls.Worksheet fotos,
    required List<String> headers,
    required List<List<String>> rows,
    required Map<int, List<String>> imagesByRow,
    required int latIdx,
    required int lngIdx,
    required List<String> warnings,
    required Map<int, int> anchorBySrcRow,
    ExportCancelToken? cancelToken,
    void Function(double ratio)? onProgress, // 0..1 relativo a esta fase
  }) {
    void ensure() {
      if (cancelToken?.canceled == true) {
        throw const FileSystemException('Exportación cancelada');
      }
    }

    final hdr = wb.styles.add('hdr_f')
      ..bold = true
      ..hAlign = xls.HAlignType.center
      ..vAlign = xls.VAlignType.center
      ..backColor = '#F1F1F1';

    final cols = ['Fila', 'Foto 1', 'Foto 2', 'Foto 3', 'Archivo', 'Lat', 'Lng', 'Mapa'];
    for (var c = 0; c < cols.length; c++) {
      final cell = fotos.getRangeByIndex(1, c + 1);
      cell.setText(cols[c]);
      cell.cellStyle = hdr;
    }
    fotos.getRangeByIndex(1, 1, 1, cols.length).rowHeight = 22;

    final total = rows.isEmpty ? 1 : rows.length;
    var out = 2;
    for (var r = 0; r < rows.length; r++) {
      ensure();
      anchorBySrcRow[r] = out;
      fotos.getRangeByIndex(out, 1).setNumber((r + 1).toDouble());

      final pics = imagesByRow[r] ?? const <String>[];
      for (var i = 0; i < pics.length && i < 3; i++) {
        ensure();
        final path = pics[i];
        try {
          final f = File(path);
          if (f.existsSync()) {
            final b = f.readAsBytesSync();
            final pic = fotos.pictures.addStream(out, 2 + i, b); // B,C,D
            pic.height = _pxToPt(140).toInt();
            pic.width = _pxToPt(186).toInt();
            fotos.getRangeByIndex(out, 2 + i).rowHeight = _pxToPt(148);
          } else {
            fotos.getRangeByIndex(out, 2 + i).setText('No encontrada');
            warnings.add('Imagen no encontrada: $path');
          }
        } catch (e) {
          fotos.getRangeByIndex(out, 2 + i).setText('Error');
          warnings.add('Error al insertar imagen: $path ($e)');
        }
      }
      if (pics.isNotEmpty) {
        fotos.getRangeByIndex(out, 5).setText(pics.first);
      }

      _writeLatLngAndLink(fotos, rows, r, out, latIdx, lngIdx);
      out++;

      if (r % 6 == 0) {
        onProgress?.call(r / total);
      }
    }
    onProgress?.call(1.0);

    for (var c = 2; c <= 4; c++) {
      fotos.getRangeByIndex(1, c).columnWidth = _pxToExcelColWidth(186 + 8);
    }
    for (var c = 1; c <= 8; c++) {
      if (c >= 2 && c <= 4) continue;
      fotos.getRangeByIndex(1, c).autoFitColumns();
    }

    final used = fotos.getRangeByIndex(1, 1, rows.isEmpty ? 2 : (rows.length + 1), cols.length);
    used.cellStyle.borders.all
      ..lineStyle = xls.LineStyle.thin
      ..color = '#DDDDDD';
    fotos.autoFilters.filterRange = used;

    // freeze panes: Range.freezePanes()
    fotos.getRangeByIndex(2, 1).freezePanes();
  }

  // ===== Miniaturas =====
  void _insertThumbnail(
      xls.Worksheet ws, {
        required int row1Based,
        required int col1Based,
        required String firstPath,
        required int thumbPx,
        required List<String> warnings,
      }) {
    try {
      final f = File(firstPath);
      if (!f.existsSync()) return;
      final Uint8List b = f.readAsBytesSync();
      final pic = ws.pictures.addStream(row1Based, col1Based, b);
      final sizePt = _pxToPt(thumbPx);
      pic.height = sizePt.toInt();
      pic.width = sizePt.toInt();
      final target = sizePt + 8;
      if (ws.getRangeByIndex(row1Based, 1).rowHeight < target) {
        ws.getRangeByIndex(row1Based, 1).rowHeight = target;
      }
    } catch (e) {
      warnings.add('Error al insertar miniatura: $firstPath ($e)');
    }
  }

  void _setPictureColumnWidth(xls.Worksheet ws, int col, {required int thumbPx}) {
    final totalPx = thumbPx + 8;
    ws.getRangeByIndex(1, col).columnWidth = _pxToExcelColWidth(totalPx);
  }

  // ===== Tipado y formatos =====
  void _setTypedFromString(xls.Range cell, String value) {
    final s = value.trim();
    if (s.isEmpty) {
      cell.setText('');
      return;
    }
    final numVal = double.tryParse(s.replaceAll(',', '.'));
    if (numVal != null) {
      cell.setNumber(numVal);
      return;
    }
    if (s.toLowerCase() == 'true' || s.toLowerCase() == 'false') {
      cell.setText(s.toUpperCase());
      return;
    }
    cell.setText(_sanitizeText(s));
  }

  (double?, double?) _extractLatLng(List<String> vals, int latIdx, int lngIdx) {
    double? parse(String? v) {
      if (v == null) return null;
      final s = v.trim();
      if (s.isEmpty) return null;
      return double.tryParse(s.replaceAll(',', '.'));
    }

    final lat = (latIdx != -1 && latIdx < vals.length) ? parse(vals[latIdx]) : null;
    final lng = (lngIdx != -1 && lngIdx < vals.length) ? parse(vals[lngIdx]) : null;
    return (lat, lng);
  }

  void _writeMapLink(xls.Worksheet ws, int row, int col, double lat, double lng) {
    final url = _googleMapsSearchUrl(lat, lng);
    ws.hyperlinks.add(ws.getRangeByIndex(row, col), xls.HyperlinkType.url, url);
  }

  void _writeLatLngAndLink(
      xls.Worksheet ws,
      List<List<String>> rows,
      int srcRow,
      int outRow,
      int latIdx,
      int lngIdx,
      ) {
    final (lat, lng) = _extractLatLng(rows[srcRow], latIdx, lngIdx);
    if (lat != null) ws.getRangeByIndex(outRow, 6).setNumber(lat);
    if (lng != null) ws.getRangeByIndex(outRow, 7).setNumber(lng);
    if (lat != null && lng != null) {
      final url = _googleMapsSearchUrl(lat, lng);
      ws.hyperlinks.add(ws.getRangeByIndex(outRow, 8), xls.HyperlinkType.url, url);
      ws.getRangeByIndex(outRow, 8).setText('Ver mapa');
    }
  }

  // ===== Paths =====
  Future<Directory> _ensureExportDir() async {
    Directory base;
    if (Platform.isWindows) {
      final user = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      final docsPath = user != null ? p.join(user, 'Documents') : null;
      base = (docsPath != null)
          ? Directory(docsPath)
          : ((await getDownloadsDirectory()) ?? await getApplicationDocumentsDirectory());
    } else {
      base = await getApplicationDocumentsDirectory();
    }
    final out = Directory(p.join(base.path, 'Bitacora', 'exports'));
    if (!await out.exists()) {
      await out.create(recursive: true);
    }
    return out;
  }

  // ===== Utilidades privadas =====
  double _pxToPt(int px) => px * 72.0 / 96.0;
  double _pxToExcelColWidth(int px) => px / 7.0;

  int _findHeader(List<String> headers, List<String> cands) {
    for (var i = 0; i < headers.length; i++) {
      final h = headers[i].trim().toLowerCase();
      for (final c in cands) {
        if (h == c.toLowerCase()) return i;
      }
    }
    return -1;
  }

  String _fileBase(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(RegExp(r'\s+'), '_').trim();

  String _sheetName(String s) {
    var v = s.replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ').trim();
    if (v.length > 31) v = v.substring(0, 31);
    return v.isEmpty ? 'Bitacora' : v;
  }

  String _sanitizeText(String s) {
    if (s.isEmpty) return s;
    const dangerous = ['=', '+', '-', '@'];
    final startsDanger =
        dangerous.any((d) => s.startsWith(d)) || s.codeUnitAt(0) <= 0x20;
    return startsDanger ? "'$s" : s;
  }

  String _googleMapsSearchUrl(double lat, double lng) {
    final q = '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
    return 'https://www.google.com/maps/search/?api=1&query=$q';
  }

  String _ts() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${now.day.toString().padLeft(2, '0')}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
