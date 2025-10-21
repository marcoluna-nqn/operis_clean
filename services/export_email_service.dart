// lib/services/export_email_service.dart
import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xls;

/// Resultado del exportador.
class ExportResult {
  final File xlsxFile;
  final XFile shareXFile;
  const ExportResult({required this.xlsxFile, required this.shareXFile});
}

/// Exporta una planilla a XLSX (compatible con Excel, Gmail/Outlook/Apple Mail).
class ExportXlsxService {
  ExportXlsxService._();
  static final ExportXlsxService instance = ExportXlsxService._();

  Future<ExportResult> exportToXlsx({
    required List<String> headers,
    required List<List<String>> rows,
    required Map<int, List<String>> imagesByRow,
    required int imageColumnIndex, // 1-based
    required String sheetName,
    bool includeImages = true,
    String altRowColor = '#FAFAFA',
    String headerColor = '#F4F4F4',
    String headerFontHex = '#111111',
  }) async {
    final safeTitle = _sanitizeSheetName(
      sheetName.isEmpty ? 'Bitacora' : sheetName,
    );

    // Rutas de salida (Documents/exports + /tmp para compartir).
    final docs = await getApplicationDocumentsDirectory();
    final exportsDir = Directory(p.join(docs.path, 'exports'));
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final outPath =
    p.join(exportsDir.path, '${_sanitizeFileBase(safeTitle)}_$stamp.xlsx');

    final tmp = await getTemporaryDirectory();
    final cachePath =
    p.join(tmp.path, '${_sanitizeFileBase(safeTitle)}_$stamp.xlsx');

    // Libro y hojas
    final wb = xls.Workbook();
    final ws = wb.worksheets[0];
    ws.name = safeTitle;

    xls.Worksheet? fotosSheet;
    if (includeImages) {
      fotosSheet = wb.worksheets.add()..name = 'Fotos';
    }

    // Estilos
    final hdr = wb.styles.add('hdr')
      ..bold = true
      ..hAlign = xls.HAlignType.center
      ..vAlign = xls.VAlignType.center
      ..backColor = headerColor
      ..fontColor = headerFontHex
      ..fontSize = 11;

    final body = wb.styles.add('body')
      ..hAlign = xls.HAlignType.left
      ..vAlign = xls.VAlignType.center
      ..fontSize = 10;

    final alt = wb.styles.add('alt')
      ..hAlign = xls.HAlignType.left
      ..vAlign = xls.VAlignType.center
      ..backColor = altRowColor
      ..fontSize = 10;

    final num6 = wb.styles.add('num6')
      ..hAlign = xls.HAlignType.center
      ..vAlign = xls.VAlignType.center
      ..numberFormat = '0.000000'
      ..fontSize = 10;

    // Header
    for (var c = 0; c < headers.length; c++) {
      final cell = ws.getRangeByIndex(1, c + 1);
      cell.setText(headers[c]);
      cell.cellStyle = hdr;
    }
    ws.getRangeByIndex(1, 1, 1, headers.length).rowHeight = 24;

    final dataCols = headers.length;
    final imgCol = imageColumnIndex.clamp(1, dataCols);
    final latIdx = _findHeaderIndex(headers, const ['lat', 'latitud', 'latitude']);
    final lngIdx =
    _findHeaderIndex(headers, const ['lng', 'lon', 'longitud', 'longitude']);
    final obsIdx = _findHeaderIndex(headers,
        const ['obs', 'observaciones', 'observación', 'observacion', 'notes', 'nota', 'notas']);

    // Cuerpo
    for (var r = 0; r < rows.length; r++) {
      final excelRow = r + 2;
      final rowVals = rows[r];

      for (var c = 0; c < dataCols && c < rowVals.length; c++) {
        final cell = ws.getRangeByIndex(excelRow, c + 1);
        cell.setText(rowVals[c]);
        cell.cellStyle = body;
      }

      // Lat/Lng numéricos + link a Maps
      if (latIdx != -1 && lngIdx != -1 && latIdx < rowVals.length && lngIdx < rowVals.length) {
        final lat = double.tryParse(rowVals[latIdx].replaceAll(',', '.'));
        final lng = double.tryParse(rowVals[lngIdx].replaceAll(',', '.'));
        if (lat != null && lng != null) {
          ws.hyperlinks.add(
            ws.getRangeByIndex(excelRow, latIdx + 1),
            xls.HyperlinkType.url,
            'https://maps.google.com/?q=$lat,$lng',
          );
          ws.getRangeByIndex(excelRow, latIdx + 1)
            ..setNumber(lat)
            ..cellStyle = num6;
          ws.getRangeByIndex(excelRow, lngIdx + 1)
            ..setNumber(lng)
            ..cellStyle = num6;
        }
      }

      // Miniatura en hoja principal (solo la primera)
      if (includeImages) {
        final pics = imagesByRow[r];
        if (pics != null && pics.isNotEmpty) {
          final f = File(pics.first);
          if (await f.exists()) {
            final bytes = await f.readAsBytes();
            final pic = ws.pictures.addStream(excelRow, imgCol, bytes);
            pic.height = 96;
            pic.width = 120;
            ws.getRangeByIndex(excelRow, 1).rowHeight = 100;
            if (ws.getRangeByIndex(1, imgCol).columnWidth < 20) {
              ws.getRangeByIndex(1, imgCol).columnWidth = 20;
            }
          } else {
            ws.getRangeByIndex(excelRow, imgCol).setText('No encontrada');
          }
        }
      }

      if (r.isOdd) {
        ws.getRangeByIndex(excelRow, 1, excelRow, dataCols).cellStyle = alt;
      }
    }

    // Ajustes para Observaciones
    if (obsIdx != -1) {
      final rngObs =
      ws.getRangeByIndex(2, obsIdx + 1, rows.length + 1, obsIdx + 1);
      rngObs.cellStyle.wrapText = true;
      if (ws.getRangeByIndex(1, obsIdx + 1).columnWidth < 30) {
        ws.getRangeByIndex(1, obsIdx + 1).columnWidth = 30;
      }
      for (var r = 0; r < rows.length; r++) {
        final excelRow = r + 2;
        if (ws.getRangeByIndex(excelRow, 1).rowHeight < 22) {
          ws.getRangeByIndex(excelRow, 1).rowHeight = 22;
        }
      }
    }

    // AutoFit (excepto columna de imagen)
    for (var c = 1; c <= dataCols; c++) {
      if (includeImages && c == imgCol) continue;
      ws.getRangeByIndex(1, c).autoFitColumns();
    }

    // Bordes suaves
    final used = ws.getRangeByIndex(1, 1, rows.length + 1, dataCols);
    used.cellStyle.borders.all
      ..lineStyle = xls.LineStyle.thin
      ..color = '#DDDDDD';

    // Hoja “Fotos” con todas las imágenes
    if (includeImages && fotosSheet != null) {
      await _fillFotosSheet(
        wb: wb,
        fotos: fotosSheet,
        headers: headers,
        rows: rows,
        imagesByRow: imagesByRow,
        latIdx: latIdx,
        lngIdx: lngIdx,
        altRowColor: altRowColor,
        headerColor: headerColor,
        headerFontHex: headerFontHex,
      );
    }

    // Guardar
    final bytes = wb.saveAsStream();
    wb.dispose();

    final file = File(outPath)..writeAsBytesSync(bytes, flush: true);
    final cacheCopy = File(cachePath)..writeAsBytesSync(bytes, flush: true);

    return ExportResult(
      xlsxFile: file,
      shareXFile: XFile(
        cacheCopy.path,
        mimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        name: p.basename(cacheCopy.path),
      ),
    );
  }

  Future<void> _fillFotosSheet({
    required xls.Workbook wb,
    required xls.Worksheet fotos,
    required List<String> headers,
    required List<List<String>> rows,
    required Map<int, List<String>> imagesByRow,
    required int latIdx,
    required int lngIdx,
    required String altRowColor,
    required String headerColor,
    required String headerFontHex,
  }) async {
    final hdr = wb.styles.add('hdr_f')
      ..bold = true
      ..hAlign = xls.HAlignType.center
      ..vAlign = xls.VAlignType.center
      ..backColor = headerColor
      ..fontColor = headerFontHex
      ..fontSize = 11;

    final body = wb.styles.add('body_f')
      ..hAlign = xls.HAlignType.left
      ..vAlign = xls.VAlignType.center
      ..fontSize = 10;

    final alt = wb.styles.add('alt_f')
      ..hAlign = xls.HAlignType.left
      ..vAlign = xls.VAlignType.center
      ..backColor = altRowColor
      ..fontSize = 10;

    final fHeaders = ['Fila', 'Foto', 'Archivo', 'Lat', 'Lng', 'Mapa'];
    for (var c = 0; c < fHeaders.length; c++) {
      final cell = fotos.getRangeByIndex(1, c + 1);
      cell.setText(fHeaders[c]);
      cell.cellStyle = hdr;
    }
    fotos.getRangeByIndex(1, 1, 1, fHeaders.length).rowHeight = 24;

    var outRow = 2;
    for (var r = 0; r < rows.length; r++) {
      final pics = imagesByRow[r] ?? const <String>[];

      if (pics.isEmpty) {
        fotos.getRangeByIndex(outRow, 1).setNumber((r + 1).toDouble());
        _writeLatLngAndLink(fotos, rows, r, outRow, latIdx, lngIdx);
        (outRow - 2).isOdd
            ? fotos
            .getRangeByIndex(outRow, 1, outRow, fHeaders.length)
            .cellStyle = alt
            : fotos
            .getRangeByIndex(outRow, 1, outRow, fHeaders.length)
            .cellStyle = body;
        outRow++;
        continue;
      }

      for (final path in pics) {
        fotos.getRangeByIndex(outRow, 1).setNumber((r + 1).toDouble());
        final f = File(path);
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          final pic = fotos.pictures.addStream(outRow, 2, bytes);
          pic.height = 160;
          pic.width = 210;
          fotos.getRangeByIndex(outRow, 2).rowHeight = 170;
          fotos.getRangeByIndex(1, 2).columnWidth = 32;
          fotos.getRangeByIndex(outRow, 3).setText(path);
        } else {
          fotos.getRangeByIndex(outRow, 2).setText('No encontrada');
          fotos.getRangeByIndex(outRow, 3).setText(path);
        }
        _writeLatLngAndLink(fotos, rows, r, outRow, latIdx, lngIdx);

        (outRow - 2).isOdd
            ? fotos
            .getRangeByIndex(outRow, 1, outRow, fHeaders.length)
            .cellStyle = alt
            : fotos
            .getRangeByIndex(outRow, 1, outRow, fHeaders.length)
            .cellStyle = body;
        outRow++;
      }
    }

    fotos.getRangeByIndex(1, 1).autoFitColumns();
    for (var c = 3; c <= 6; c++) {
      fotos.getRangeByIndex(1, c).autoFitColumns();
    }

    final used = fotos.getRangeByIndex(1, 1, outRow - 1, fHeaders.length);
    used.cellStyle.borders.all
      ..lineStyle = xls.LineStyle.thin
      ..color = '#DDDDDD';
  }

  void _writeLatLngAndLink(
      xls.Worksheet ws,
      List<List<String>> rows,
      int srcRow,
      int outRow,
      int latIdx,
      int lngIdx,
      ) {
    double? lat, lng;
    if (latIdx != -1 && latIdx < rows[srcRow].length) {
      lat = double.tryParse(rows[srcRow][latIdx].replaceAll(',', '.'));
    }
    if (lngIdx != -1 && lngIdx < rows[srcRow].length) {
      lng = double.tryParse(rows[srcRow][lngIdx].replaceAll(',', '.'));
    }

    if (lat != null) ws.getRangeByIndex(outRow, 4).setNumber(lat);
    if (lng != null) ws.getRangeByIndex(outRow, 5).setNumber(lng);

    if (lat != null && lng != null) {
      final url = 'https://maps.google.com/?q=${lat.toStringAsFixed(6)},'
          '${lng.toStringAsFixed(6)}';
      ws.hyperlinks.add(ws.getRangeByIndex(outRow, 6), xls.HyperlinkType.url, url);
      ws.getRangeByIndex(outRow, 6).setText('Ver mapa');
    }
  }

  int _findHeaderIndex(List<String> headers, List<String> candidates) {
    for (var i = 0; i < headers.length; i++) {
      final h = headers[i].trim().toLowerCase();
      for (final cand in candidates) {
        if (h == cand.toLowerCase()) return i;
      }
    }
    return -1;
  }

  String _sanitizeFileBase(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(RegExp(r'\s+'), '_').trim();

  String _sanitizeSheetName(String s) {
    if (s.isEmpty) return 'Bitacora';
    var v = s.replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ').trim();
    if (v.length > 31) v = v.substring(0, 31);
    return v.isEmpty ? 'Bitacora' : v;
  }
}

/// Compartir el XLSX con el share sheet del SO (Gmail/Outlook/Mail, etc.)
class ExportMailer {
  static Future<void> shareXlsx(
      ExportResult result, {
        String subject = 'Reporte Gridnote',
        String body = 'Adjunto XLSX generado con Gridnote.',
      }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [result.shareXFile],
        subject: subject,
        text: body,
      ),
    );
  }
}

/// Pequeño overlay para feedback del usuario durante el export.
class ExportFlow {
  static Future<void> exportAndShareWithUI(
      BuildContext context, {
        required List<String> headers,
        required List<List<String>> rows,
        required Map<int, List<String>> imagesByRow,
        required int imageColumnIndex,
        required String sheetName,
        String subject = 'Reporte Gridnote',
        String body = 'Adjunto XLSX generado con Gridnote.',
        bool emailSafe = false,
      }) async {
    final handle = _showOverlay(context, message: 'Generando XLSX…');
    try {
      final result = await ExportXlsxService.instance.exportToXlsx(
        headers: headers,
        rows: rows,
        imagesByRow: imagesByRow,
        imageColumnIndex: imageColumnIndex,
        sheetName: sheetName,
        includeImages: !emailSafe,
      );
      handle.update('Compartiendo…');
      await ExportMailer.shareXlsx(result, subject: subject, body: body);
      await handle.complete('Listo');
    } catch (e) {
      await handle.fail('Error: $e');
      rethrow;
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      handle.hide();
    }
  }

  static _OverlayHandle _showOverlay(BuildContext context, {String message = 'Procesando…'}) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return _OverlayHandle.noop();
    final key = GlobalKey<_OverlayContentState>();
    final entry = OverlayEntry(
      builder: (_) => _OverlayDim(
        child: Center(child: _OverlayContent(key: key, initialMessage: message)),
      ),
    );
    overlay.insert(entry);
    return _OverlayHandle(entry: entry, key: key);
  }
}

class _OverlayHandle {
  final OverlayEntry? entry;
  final GlobalKey<_OverlayContentState>? key;
  _OverlayHandle({required this.entry, required this.key});
  _OverlayHandle.noop()
      : entry = null,
        key = null;

  void update(String msg) => key?.currentState?.update(msg);
  Future<void> complete(String msg) async =>
      key?.currentState != null ? key!.currentState!.complete(msg) : Future.value();
  Future<void> fail(String msg) async =>
      key?.currentState != null ? key!.currentState!.fail(msg) : Future.value();
  void hide() => entry?.remove();
}

class _OverlayDim extends StatelessWidget {
  final Widget child;
  const _OverlayDim({required this.child});
  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(color: Colors.black.withValues(alpha: 0.25)),
        ),
      ),
      Center(child: child),
    ]);
  }
}

class _OverlayContent extends StatefulWidget {
  final String initialMessage;
  const _OverlayContent({super.key, required this.initialMessage});
  @override
  State<_OverlayContent> createState() => _OverlayContentState();
}

class _OverlayContentState extends State<_OverlayContent> with TickerProviderStateMixin {
  late final AnimationController _pulse =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  late final AnimationController _spin =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat();

  String _message = '';
  bool _done = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _message = widget.initialMessage;
    unawaited(HapticFeedback.selectionClick());
  }

  void update(String msg) {
    setState(() => _message = msg);
    unawaited(HapticFeedback.selectionClick());
  }

  Future<void> complete(String msg) async {
    setState(() {
      _message = msg;
      _done = true;
      _error = false;
    });
    unawaited(HapticFeedback.lightImpact());
    await Future<void>.delayed(const Duration(milliseconds: 650));
  }

  Future<void> fail(String msg) async {
    setState(() {
      _message = msg;
      _error = true;
      _done = false;
    });
    unawaited(HapticFeedback.mediumImpact());
    await Future<void>.delayed(const Duration(milliseconds: 900));
  }

  @override
  void dispose() {
    _pulse.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(blurRadius: 24, offset: Offset(0, 10), color: Colors.black26)
        ],
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: Tween(begin: 0.95, end: 1.05)
                .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (c, a) =>
                  FadeTransition(opacity: a, child: ScaleTransition(scale: a, child: c)),
              child: _done
                  ? const Icon(Icons.check_circle_rounded, key: ValueKey('ok'), size: 56)
                  : _error
                  ? const Icon(Icons.error_rounded, key: ValueKey('err'), size: 56)
                  : RotationTransition(
                key: const ValueKey('spin'),
                turns: _spin,
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: CustomPaint(painter: _SpinnerPainter()),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
            child: Text(
              _message,
              key: ValueKey(_message),
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final center = Offset(size.width / 2, size.height / 2);

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = Colors.black12;
    canvas.drawCircle(center, r - 2, base);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = Colors.black.withValues(alpha: 0.35);

    const sweep = 3 * 3.14159 / 2;
    final rect = Rect.fromCircle(center: center, radius: r - 2);
    canvas.drawArc(rect, -3.14159 / 2, sweep, false, arc);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
