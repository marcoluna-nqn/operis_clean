// lib/services/excel_exporter.dart
import 'dart:typed_data';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xls;

class SheetData {
  final String title;
  final List<String> headers;
  final List<List<String>> rows;
  SheetData({required this.title, required this.headers, required this.rows});
}

class ExcelExporter {
  static Future<Uint8List> buildXlsx({
    required SheetData data,
    Uint8List? logoPng,
    String companyName = 'Bitácora',
    String contactLine = 'contacto@empresa.com',
  }) async {
    final wb = xls.Workbook();

    // -------- Portada --------
    final cover = wb.worksheets[0];
    cover.name = 'Portada';
    for (var c = 1; c <= 8; c++) {
      cover.getRangeByIndex(1, c).columnWidth = 18;
    }

    if (logoPng != null && logoPng.isNotEmpty) {
      cover.pictures.addStream(1, 1, logoPng); // fila, col, bytes
      final pic = cover.pictures[0];
      pic.height = 80;
      pic.width = 80;
    }

    final titleRange = cover.getRangeByName('B1:F2')..merge();
    titleRange.setText(companyName);
    titleRange.cellStyle
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
      ['Cantidad de columnas', data.headers.length.toString()],
      ['Cantidad de filas', data.rows.length.toString()],
    ];
    var rr = 6;
    for (final m in metrics) {
      cover.getRangeByIndex(rr, 2).setText('• ${m[0]}');
      cover.getRangeByIndex(rr, 4).setText(m[1]);
      rr++;
    }

    // -------- Datos --------
    final sheet = wb.worksheets.addWithName('Datos');
    final cols = data.headers.length;
    final rows = data.rows.length;

    // Encabezados
    for (var c = 0; c < cols; c++) {
      sheet.getRangeByIndex(1, c + 1).setText(data.headers[c]);
    }
    _styleHeader(sheet.getRangeByIndex(1, 1, 1, cols));

    // Filas
    for (var i = 0; i < rows; i++) {
      for (var c = 0; c < cols; c++) {
        sheet
            .getRangeByIndex(i + 2, c + 1)
            .setText(c < data.rows[i].length ? data.rows[i][c] : '');
      }
    }

    // Tabla (filtros + bandas)
    final endCell = _a1(cols, rows + 1);
    final tableRange = sheet.getRangeByName('A1:$endCell');
    final table = sheet.tableCollection.create('TablaDatos', tableRange);
    table.builtInTableStyle = xls.ExcelTableBuiltInStyle.tableStyleMedium9;

    // Auto-fit
    sheet.getRangeByIndex(1, 1, rows + 1, cols).autoFitColumns();

    // -------- Totales (fuera de la tabla, con SUBTOTAL) --------
    final totalsRow = rows + 3; // 1 encabezado + rows + 1 línea en blanco
    sheet.getRangeByIndex(totalsRow, 1).setText('Totales:');
    sheet.getRangeByIndex(totalsRow, 1).cellStyle.bold = true;

    for (var c = 0; c < cols; c++) {
      if (_columnSeemsNumeric(data.rows, c)) {
        final colA1 = _colLetters(c + 1);
        final firstData = 2; // comienza en fila 2
        final lastData = rows + 1;
        sheet
            .getRangeByIndex(totalsRow, c + 1)
            .setFormula('=SUBTOTAL(109,$colA1$firstData:$colA1$lastData)');
        sheet.getRangeByIndex(totalsRow, c + 1).cellStyle.bold = true;
      }
    }
    // Estética totales
    final trRange = sheet.getRangeByIndex(totalsRow, 1, totalsRow, cols);
    trRange.cellStyle
      ..backColor = '#F3F4F6'
      ..borders.all.lineStyle = xls.LineStyle.thin
      ..borders.all.color = '#CCCCCC';

    // -------- Resumen --------
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
    // Cuenta filas visibles usando la primera columna
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

  // -------- helpers --------
  static void _styleHeader(xls.Range range) {
    range.cellStyle.bold = true;
    range.cellStyle.hAlign = xls.HAlignType.center;
    range.cellStyle.vAlign = xls.VAlignType.center;
    range.cellStyle.backColor = '#F3F4F6';
    range.cellStyle.borders.all.lineStyle = xls.LineStyle.thin;
    range.cellStyle.borders.all.color = '#CCCCCC';
  }

  static void _paintPanel(xls.Range r) {
    r.cellStyle.backColor = '#F8FAFC';
    r.cellStyle.borders.all.lineStyle = xls.LineStyle.thin;
    r.cellStyle.borders.all.color = '#E5E7EB';
  }

  static bool _columnSeemsNumeric(List<List<String>> rows, int colIndex) {
    int count = 0, numeric = 0;
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

  static String _a1(int colCount, int row) => '${_colLetters(colCount)}$row';

  static String _colLetters(int colIdx) {
    var c = colIdx;
    final buf = StringBuffer();
    while (c > 0) {
      final rem = (c - 1) % 26;
      buf.writeCharCode(65 + rem);
      c = (c - 1) ~/ 26;
    }
    return buf.toString().split('').reversed.join();
  }

  static String _fmtDateTime(DateTime d) =>
      '${_pad(d.day)}/${_pad(d.month)}/${d.year} ${_pad(d.hour)}:${_pad(d.minute)}';
  static String _pad(int n) => n.toString().padLeft(2, '0');
}
