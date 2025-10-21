import 'dart:io' as io;

import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Genera un PNG “estilo Excel” para previsualizar en el correo.
/// Encabezados + filas y columnas de fotos (Foto 1..N).
class MailPreviewService {
  const MailPreviewService();

  Future<io.File> generate({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    required Map<int, List<String>> imagesByRow,
    int maxRows = 30,
  }) async {
    // Layout
    const headerHeight = 44;
    const rowHeight = 64;

    int widthForCol(String h) {
      final hl = h.trim().toLowerCase();
      if (hl.startsWith('foto')) return 140;
      if (hl == 'lat' || hl == 'lng') return 120;
      return 160;
    }

    final colWidths = headers.map(widthForCol).toList();
    final totalW = colWidths.fold<int>(0, (a, b) => a + b);
    const cap = 2000;
    final finalColW = (totalW > cap)
        ? colWidths.map((w) => (w * (cap / totalW)).floor().clamp(80, 180)).toList()
        : List<int>.from(colWidths);

    final columns = headers.length;
    final shownRows = rows.take(maxRows).toList();
    final w = finalColW.fold<int>(0, (a, b) => a + b);
    final h = 20 + 24 + 8 + headerHeight + shownRows.length * rowHeight + 20;

    // Colores
    final white = img.ColorRgb8(255, 255, 255);
    final black = img.ColorRgb8(17, 17, 17);
    final grid = img.ColorRgb8(217, 217, 217);
    final headBg = img.ColorRgb8(242, 242, 242);

    // Canvas
    final canvas = img.Image(width: w + 40, height: h);
    img.fill(canvas, color: white);

    // Fuentes
    final fTitle = img.arial24;
    final fHeader = img.arial14;
    final fCell = img.arial14;

    final int x0 = 20;
    int y = 20;

    // Título
    _drawBox(canvas, x0, y, x0 + w, y + 24, fill: white, outline: grid);
    img.drawString(canvas, title, x: x0 + 8, y: y + 4, font: fTitle, color: black);
    y += 24 + 8;

    // Encabezado
    _drawBox(canvas, x0, y, x0 + w, y + headerHeight, fill: headBg, outline: grid);
    var cx = x0;
    for (var c = 0; c < columns; c++) {
      final cw = finalColW[c];
      _drawBox(canvas, cx, y, cx + cw, y + headerHeight, fill: headBg, outline: grid);
      img.drawString(canvas, headers[c].isEmpty ? ' ' : headers[c],
          x: cx + 8, y: y + 12, font: fHeader, color: black);
      cx += cw;
    }
    y += headerHeight;

    // Filas
    for (var r = 0; r < shownRows.length; r++) {
      final row = shownRows[r];
      cx = x0;
      for (var c = 0; c < columns; c++) {
        final cw = finalColW[c];
        _drawBox(canvas, cx, y, cx + cw, y + rowHeight, fill: white, outline: grid);

        final header = headers[c].trim().toLowerCase();
        final isPhoto = header.startsWith('foto');

        if (isPhoto) {
          final idxStr = header.replaceAll(RegExp(r'[^0-9]'), '');
          final picIdx = (int.tryParse(idxStr) ?? 1) - 1;
          final pics = imagesByRow[r] ?? const <String>[];
          if (picIdx >= 0 && picIdx < pics.length) {
            final path = pics[picIdx];
            try {
              final decoded = img.decodeImage(await io.File(path).readAsBytes());
              if (decoded != null) {
                final targetW = cw - 16;
                final targetH = rowHeight - 16;
                final sc = _min(targetW / decoded.width, targetH / decoded.height);
                final newW = (decoded.width * sc).round().clamp(1, targetW);
                final newH = (decoded.height * sc).round().clamp(1, targetH);
                final thumb = img.copyResize(decoded,
                    width: newW, height: newH, interpolation: img.Interpolation.cubic);
                final dx = cx + ((cw - thumb.width) ~/ 2);
                final dy = y + ((rowHeight - thumb.height) ~/ 2);
                img.compositeImage(canvas, thumb, dstX: dx, dstY: dy);
              } else {
                img.drawString(canvas, '—', x: cx + 6, y: y + 12, font: fCell, color: black);
              }
            } catch (_) {
              img.drawString(canvas, '—', x: cx + 6, y: y + 12, font: fCell, color: black);
            }
          }
        } else {
          final txt = (c < row.length ? row[c] : '').trim();
          img.drawString(canvas, txt.isEmpty ? ' ' : txt,
              x: cx + 8, y: y + 12, font: fCell, color: black);
        }

        cx += cw;
      }
      y += rowHeight;
    }

    // Guardar
    final tmp = await getTemporaryDirectory();
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = io.File(p.join(tmp.path, '${_sanitize(title)}_$ts.png'))
      ..writeAsBytesSync(img.encodePng(canvas), flush: true);
    return file;
  }

  // Helpers
  void _drawBox(img.Image dst, int x1, int y1, int x2, int y2,
      {required img.ColorRgb8 fill, img.ColorRgb8? outline}) {
    img.fillRect(dst, x1: x1, y1: y1, x2: x2, y2: y2, color: fill);
    if (outline != null) {
      img.drawRect(dst, x1: x1, y1: y1, x2: x2, y2: y2, color: outline);
    }
  }

  double _min(double a, double b) => (a < b) ? a : b;

  String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(RegExp(r'\s+'), '_');
}
