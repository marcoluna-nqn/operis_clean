// lib/services/excel_exporter_bex.dart
//
// Exportador “premium” con paquete BEX (Bundle EXport):
// - XLSX (Syncfusion XlsIO)
// - CSV (compatible Excel/Google Sheets)
// - JSON (schema simple)
// - meta.json (metadatos del bundle)
// - preview.png (opcional, portada/render externo)
//
// ⚠ Requiere en pubspec:
//   syncfusion_flutter_xlsio: ^28.2.12
//   archive: ^4.0.7
//
// Uso típico:
//   final x = await ExcelExporterBex.buildXlsxPremium(data: d, logoPng: png);
//   final bex = await ExcelExporterBex.buildBexBundle(data: d, logoPng: png, previewPng: thumb);
//   // Guardar/compartir bytes…

import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xls;

class SheetData {
  final String title;
  final List<String> headers;
  final List<List<String>> rows;
  SheetData({
    required this.title,
    required this.headers,
    required this.rows,
  });
}

class ExcelExporterBex {
  // ===================== XLSX PREMIUM ======================
  static Future<Uint8List> buildXlsxPremium({
    required SheetData data,
    Uint8List? logoPng,
    String companyName = 'Bitácora',
    String contactLine = 'contacto@empresa.com',
  }) async {
    final wb = xls.Workbook();

    // ---------- Hoja Portada ----------
    final cover = wb.worksheets[0];
    cover.name = 'Portada';
    for (var c = 1; c <= 8; c++) {
      cover.getRangeByIndex(1, c).columnWidth = 18;
    }

    if (logoPng != null && logoPng.isNotEmpty) {
      // (fila, columna, bytes)
      cover.pictures.addStream(1, 1, logoPng);
      final pic = cover.pictures[0];
      pic.height = 80;
      pic.width = 80;
    }

    final title = cover.getRangeByName('B1:F2')..merge();
    title.setText(companyName);
    title.cellStyle
      ..fontSize = 22
      ..bold = true
      ..hAlign = xls.HAlignType.left
      ..vAlign = xls.VAlignType.center;

    final sub = cover.getRangeByName('B3:F3')..merge();
    sub.setText(data.title);
    sub.cellStyle
      ..fontSize = 14
      ..hAlign = xls.HAlignType.left
      ..vAlign = xls.VAlignType.center;

    final contact = cover.getRangeByName('B4:F4')..merge();
    contact.setText(contactLine);

    final panel = cover.getRangeByName('B6:F10')..merge();
    _paintPanel(panel);

    final now = DateTime.now();
    final metrics = [
      ['Fecha de exportación', _fmtDateTime(now)],
      ['Cantidad de columnas', '${data.headers.length}'],
      ['Cantidad de filas', '${data.rows.length}'],
    ];
    var r = 6;
    for (final m in metrics) {
      cover.getRangeByIndex(r, 2).setText('• ${m[0]}');
      cover.getRangeByIndex(r, 4).setText(m[1]);
      r++;
    }

    // ---------- Hoja Datos ----------
    final sheet = wb.worksheets.addWithName('Datos');
    final cols = data.headers.length;
    final rows = data.rows.length;

    // Encabezados
    for (var c = 0; c < cols; c++) {
      sheet.getRangeByIndex(1, c + 1).setText(data.headers[c]);
    }
    _styleHeader(sheet.getRangeByIndex(1, 1, 1, cols));

    // Celdas
    for (var i = 0; i < rows; i++) {
      for (var c = 0; c < cols; c++) {
        final v = c < data.rows[i].length ? data.rows[i][c] : '';
        sheet.getRangeByIndex(i + 2, c + 1).setText(v);
      }
    }

    // Tabla con filtros/bandas
    final endCell = _a1(cols, rows + 1);
    final rng = sheet.getRangeByName('A1:$endCell');
    final table = sheet.tableCollection.create('TablaDatos', rng);
    table.builtInTableStyle = xls.ExcelTableBuiltInStyle.tableStyleMedium9;

    // Ajuste de columnas
    sheet.getRangeByIndex(1, 1, rows + 1, cols).autoFitColumns();

    // Totales con SUBTOTAL (respeta filtros)
    final totalsRow = rows + 3;
    sheet.getRangeByIndex(totalsRow, 1).setText('Totales:');
    sheet.getRangeByIndex(totalsRow, 1).cellStyle.bold = true;

    for (var c = 0; c < cols; c++) {
      if (_columnSeemsNumeric(data.rows, c)) {
        final colA1 = _colLetters(c + 1);
        final firstData = 2;
        final lastData = rows + 1;
        sheet
            .getRangeByIndex(totalsRow, c + 1)
            .setFormula('=SUBTOTAL(109,$colA1$firstData:$colA1$lastData)');
        sheet.getRangeByIndex(totalsRow, c + 1).cellStyle.bold = true;
      }
    }
    final tr = sheet.getRangeByIndex(totalsRow, 1, totalsRow, cols);
    tr.cellStyle
      ..backColor = '#F3F4F6'
      ..borders.all.lineStyle = xls.LineStyle.thin
      ..borders.all.color = '#CCCCCC';

    // ---------- Hoja Resumen ----------
    final summary = wb.worksheets.addWithName('Resumen');
    for (var c = 1; c <= 6; c++) {
      summary.getRangeByIndex(1, c).columnWidth = 18;
    }
    summary.getRangeByName('A1:D1').merge();
    summary.getRangeByName('A1').setText('Resumen');
    summary.getRangeByName('A1').cellStyle
      ..bold = true
      ..fontSize = 16;

    summary.getRangeByName('A3').setText('Total de filas');
    summary
        .getRangeByName('B3')
        .setFormula('=SUBTOTAL(103,Datos!A2:A${rows + 1})');

    summary.getRangeByName('A4').setText('Total de columnas');
    summary.getRangeByName('B4').setNumber(cols.toDouble());

    if (cols > 0 && _columnSeemsNumeric(data.rows, cols - 1)) {
      final lastH = data.headers[cols - 1];
      final colA1 = _colLetters(cols);
      summary.getRangeByName('A6').setText('Suma de "$lastH"');
      summary
          .getRangeByName('B6')
          .setFormula('=SUBTOTAL(109,Datos!${colA1}2:$colA1${rows + 1})');
      summary.getRangeByName('A7').setText('Promedio de "$lastH"');
      summary
          .getRangeByName('B7')
          .setFormula('=SUBTOTAL(101,Datos!${colA1}2:$colA1${rows + 1})');
    }

    final bytes = wb.saveAsStream();
    wb.dispose();
    return Uint8List.fromList(bytes);
  }

  // ===================== BEX BUNDLE ======================
  static Future<Uint8List> buildBexBundle({
    required SheetData data,
    Uint8List? logoPng,
    Uint8List? previewPng,
    String companyName = 'Bitácora',
    String contactLine = 'contacto@empresa.com',
    String xlsxFileName = 'bitacora.xlsx',
    String csvFileName = 'bitacora.csv',
    String jsonFileName = 'bitacora.json',
  }) async {
    // 1) XLSX
    final xlsxBytes = await buildXlsxPremium(
      data: data,
      logoPng: logoPng,
      companyName: companyName,
      contactLine: contactLine,
    );

    // 2) CSV
    final csv = _toCsv(data);
    final csvBytes = Uint8List.fromList(utf8.encode(csv));

    // 3) JSON
    final jsonMap = {
      'title': data.title,
      'headers': data.headers,
      'rows': data.rows,
      'generatedAt': DateTime.now().toIso8601String(),
      'format': 'BEX/1',
    };
    final jsonBytes = Uint8List.fromList(utf8.encode(jsonEncode(jsonMap)));

    // 4) Metadatos del bundle
    final meta = {
      'app': 'Bitácora',
      'bundle': 'BEX',
      'version': 1,
      'company': companyName,
      'contact': contactLine,
      'files': {
        'xlsx': xlsxFileName,
        'csv': csvFileName,
        'json': jsonFileName,
        if (previewPng != null) 'preview': 'preview.png',
      },
    };
    final metaBytes = Uint8List.fromList(utf8.encode(jsonEncode(meta)));

    // 5) ZIP (.bex)
    final archive = Archive()
      ..addFile(ArchiveFile(xlsxFileName, xlsxBytes.length, xlsxBytes))
      ..addFile(ArchiveFile(csvFileName, csvBytes.length, csvBytes))
      ..addFile(ArchiveFile(jsonFileName, jsonBytes.length, jsonBytes))
      ..addFile(ArchiveFile('meta.json', metaBytes.length, metaBytes));

    if (previewPng != null && previewPng.isNotEmpty) {
      archive.addFile(ArchiveFile('preview.png', previewPng.length, previewPng));
    }

    final encoder = ZipEncoder();
    final output = encoder.encode(archive);
    return Uint8List.fromList(output);
  }

  // ===================== Helpers ======================
  static void _styleHeader(xls.Range range) {
    range.cellStyle.bold = true;
    range.cellStyle.hAlign = xls.HAlignType.center;
    range.cellStyle.vAlign = xls.VAlignType.center;
    range.cellStyle.backColor = '#F3F4F6';
    range.cellStyle.borders.all.lineStyle = xls.LineStyle.thin;
    range.cellStyle.borders.all.color = '#CCCCCC';
    range.cellStyle.wrapText = true; // API válida: via cellStyle
  }

  static void _paintPanel(xls.Range r) {
    r.cellStyle.backColor = '#F8FAFC';
    r.cellStyle.borders.all.lineStyle = xls.LineStyle.thin;
    r.cellStyle.borders.all.color = '#E5E7EB';
  }

  static bool _columnSeemsNumeric(List<List<String>> rows, int colIndex) {
    var count = 0, numeric = 0;
    for (final row in rows) {
      if (colIndex >= row.length) continue;
      final v = row[colIndex].trim();
      if (v.isEmpty) continue;
      count++;
      final n = double.tryParse(v.replaceAll(',', '.'));
      if (n != null) numeric++;
    }
    if (count == 0) return false;
    return numeric / count >= 0.8;
  }

  static String _a1(int col, int row) => '${_colLetters(col)}$row';

  static String _colLetters(int colIdx) {
    var c = colIdx;
    final chars = <int>[];
    while (c > 0) {
      final rem = (c - 1) % 26;
      chars.add(65 + rem);
      c = (c - 1) ~/ 26;
    }
    final colStr = String.fromCharCodes(chars.reversed);
    return colStr;
  }

  static String _fmtDateTime(DateTime d) =>
      '${_pad(d.day)}/${_pad(d.month)}/${d.year} ${_pad(d.hour)}:${_pad(d.minute)}';
  static String _pad(int n) => n.toString().padLeft(2, '0');

  static String _toCsv(SheetData data) {
    final buf = StringBuffer();
    void writeRow(List<String> row) {
      for (var i = 0; i < row.length; i++) {
        if (i > 0) buf.write(',');
        buf.write(_csvEscape(row[i]));
      }
      buf.writeln();
    }

    writeRow(data.headers);
    for (final r in data.rows) {
      // Normaliza el largo a cantidad de headers
      final out = List<String>.generate(
        data.headers.length,
            (i) => i < r.length ? r[i] : '',
      );
      writeRow(out);
    }
    return buf.toString();
  }

  static String _csvEscape(String v) {
    final needsQuotes =
        v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r');
    final s = v.replaceAll('"', '""');
    return needsQuotes ? '"$s"' : s;
  }
}
