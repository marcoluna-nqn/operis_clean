import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xls;

class StickerGeo {
  const StickerGeo(this.lat, this.lng);
  final double? lat;
  final double? lng;
}

/// Exporta un XLSX que respeta tu grilla: texto + Lat/Lng + miniaturas en la MISMA fila.
class GridStickerXlsxService {
  const GridStickerXlsxService();

  Future<File> export({
    required String sheetTitle,
    required List<String> baseHeaders,
    required List<List<String>> baseRows,
    required Map<int, List<String>> imagesByRow,
    List<StickerGeo?>? coordsByRow,
    int maxPhotosPerRow = 5,
    double thumbWidth = 96,
    double thumbHeight = 72,
  }) async {
    final workbook = xls.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = _safeSheetName(sheetTitle);

    // cuántas columnas de fotos realmente se usan (capadas por maxPhotosPerRow)
    final int usedPhotoCols = (imagesByRow.values.fold<int>(
      0,
          (m, l) => l.length > m ? l.length : m,
    )).clamp(0, maxPhotosPerRow);

    // encabezados: columnas base + lat/lng + fotos
    final headers = <String>[
      ...baseHeaders,
      'Lat',
      'Lng',
      for (var i = 0; i < usedPhotoCols; i++) 'Foto ${i + 1}',
    ];

    // estilos
    final sHeader = workbook.styles.add('hdr')
      ..bold = true
      ..hAlign = xls.HAlignType.center
      ..vAlign = xls.VAlignType.center
      ..backColor = '#2B2B2B'
      ..fontColor = '#FFFFFF'
      ..borders.all.lineStyle = xls.LineStyle.thin
      ..borders.all.color = '#555555';

    final sBody = workbook.styles.add('body')
      ..hAlign = xls.HAlignType.left
      ..vAlign = xls.VAlignType.center
      ..borders.all.lineStyle = xls.LineStyle.hair
      ..borders.all.color = '#444444';

    // pinta encabezados
    for (var c = 0; c < headers.length; c++) {
      sheet.getRangeByIndex(1, c + 1).setText(headers[c]);
    }
    sheet.getRangeByIndex(1, 1, 1, headers.length).cellStyle = sHeader;
    // Algunas versiones no tienen freezePanes:
    // sheet.freezePanes(2, 1);

    // datos
    const dataStartRow = 2;
    for (var r = 0; r < baseRows.length; r++) {
      final rowIdx = dataStartRow + r;
      final cells = baseRows[r];

      // columnas base
      for (var c = 0; c < baseHeaders.length; c++) {
        sheet.getRangeByIndex(rowIdx, c + 1).setText(c < cells.length ? cells[c] : '');
      }

      // lat/lng
      final g = (coordsByRow != null && r < coordsByRow.length) ? coordsByRow[r] : null;
      sheet.getRangeByIndex(rowIdx, baseHeaders.length + 1).setText(g?.lat?.toStringAsFixed(6) ?? '');
      sheet.getRangeByIndex(rowIdx, baseHeaders.length + 2).setText(g?.lng?.toStringAsFixed(6) ?? '');

      // fotos
      for (var i = 0; i < usedPhotoCols; i++) {
        final list = imagesByRow[r] ?? const <String>[];
        if (i >= list.length) continue;

        final f = File(list[i]);
        if (!f.existsSync()) continue;

        final bytes = f.readAsBytesSync();
        final col = baseHeaders.length + 3 + i;

        final pic = sheet.pictures.addStream(rowIdx, col, bytes);
        // En XlsIO (Flutter) width/height son enteros:
        pic.width = thumbWidth.toInt();
        pic.height = thumbHeight.toInt();

        // Ajusta la altura de la fila para que no corte la miniatura
        sheet.getRangeByIndex(rowIdx, 1).rowHeight =
            (thumbHeight > 24 ? thumbHeight + 6 : 24).toDouble();
      }
    }

    // estilo cuerpo
    sheet
        .getRangeByIndex(dataStartRow, 1, dataStartRow + baseRows.length - 1, headers.length)
        .cellStyle = sBody;

    // anchos de columnas de texto
    for (var c = 0; c < baseHeaders.length; c++) {
      sheet.autoFitColumn(c + 1);
      if (sheet.getRangeByIndex(1, c + 1).columnWidth < 12) {
        sheet.getRangeByIndex(1, c + 1).columnWidth = 12;
      }
    }
    // lat/lng
    sheet.getRangeByIndex(1, baseHeaders.length + 1).columnWidth = 12;
    sheet.getRangeByIndex(1, baseHeaders.length + 2).columnWidth = 12;

    // columnas de fotos
    for (var i = 0; i < usedPhotoCols; i++) {
      final col = baseHeaders.length + 3 + i;
      sheet.getRangeByIndex(1, col).columnWidth =
          (thumbWidth / 7).clamp(12, 40).toDouble();
    }

    // guarda
    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '${_sanitize(sheetTitle)}_${_ts()}.xlsx'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static String _safeSheetName(String s) {
    final t = s.replaceAll(RegExp(r'[:\\/?*\[\]]'), '').trim();
    return t.isEmpty ? 'Bitacora' : (t.length > 31 ? t.substring(0, 31) : t);
  }

  static String _sanitize(String s) {
    final x = s.replaceAll(RegExp(r'[^\w\s.-]'), '').replaceAll(RegExp(r'\s+'), '_');
    return x.isEmpty ? 'Bitacora' : x;
  }

  static String _ts() {
    final n = DateTime.now();
    String t(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${t(n.month)}${t(n.day)}_${t(n.hour)}${t(n.minute)}${t(n.second)}';
  }
}
