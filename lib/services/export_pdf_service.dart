import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf;

/// PDF “calcomanía” para que el mail muestre la grilla igual que en la app.
class ExportPdfService {
  const ExportPdfService();

  Future<File> generateUnifiedPdf({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    required Map<int, List<String>> imagesByRow,
    int thumbsPerRow = 3,
    double thumbW = 90,
    double thumbH = 68,
  }) async {
    final doc = pw.Document();

    final totalCols = headers.isEmpty ? 1 : headers.length;
    final int textCols = totalCols > thumbsPerRow ? (totalCols - thumbsPerRow) : 1;

    final theme = pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
    );

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.fromLTRB(24, 28, 24, 28),
          textDirection: pw.TextDirection.ltr,
          orientation: pw.PageOrientation.portrait,
          theme: theme,
        ),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Container(
              color: const pdf.PdfColor.fromInt(0xFFEEEEEE),
              padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Expanded(
                    child: pw.Row(
                      children: List.generate(textCols, (c) {
                        final h = c < headers.length ? headers[c] : 'Col ${c + 1}';
                        return pw.Expanded(
                          child: pw.Text(h, style: const pw.TextStyle(fontSize: 10)),
                        );
                      }),
                    ),
                  ),
                  if (thumbsPerRow > 0) pw.SizedBox(width: 10),
                  if (thumbsPerRow > 0)
                    pw.Row(
                      children: List.generate(thumbsPerRow, (i) {
                        final idx = textCols + i;
                        final h = idx < headers.length ? headers[idx] : 'Foto ${i + 1}';
                        return pw.Container(
                          width: thumbW,
                          alignment: pw.Alignment.centerLeft,
                          margin: const pw.EdgeInsets.only(right: 6),
                          child: pw.Text(h, style: const pw.TextStyle(fontSize: 10)),
                        );
                      }),
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 4),
          ],
        ),
        build: (_) => [
          ...List.generate(rows.length, (r) {
            final cells = rows[r];
            return pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              margin: const pw.EdgeInsets.only(bottom: 2),
              decoration: pw.BoxDecoration(
                color: r.isOdd ? const pdf.PdfColor.fromInt(0xFFF7F7F7) : pdf.PdfColors.white,
                border: pw.Border.all(color: const pdf.PdfColor.fromInt(0xFFDDDDDD), width: 0.3),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: List.generate(textCols, (c) {
                        final v = c < cells.length ? cells[c] : '';
                        return pw.Expanded(
                          child: pw.Padding(
                            padding: const pw.EdgeInsets.only(right: 6),
                            child: pw.Text(
                              v,
                              maxLines: 3,
                              overflow: pw.TextOverflow.clip,
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  if (thumbsPerRow > 0) pw.SizedBox(width: 10),
                  if (thumbsPerRow > 0)
                    pw.Row(
                      children: List.generate(thumbsPerRow, (i) {
                        final imgPath = (imagesByRow[r] ?? const <String>[]).length > i
                            ? imagesByRow[r]![i]
                            : null;
                        if (imgPath == null || !File(imgPath).existsSync()) {
                          return pw.Container(
                            width: thumbW,
                            height: thumbH,
                            alignment: pw.Alignment.center,
                            margin: const pw.EdgeInsets.only(right: 6),
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(color: const pdf.PdfColor.fromInt(0xFFCCCCCC), width: 0.3),
                            ),
                            child: pw.Text('—', style: const pw.TextStyle(fontSize: 8, color: pdf.PdfColors.grey)),
                          );
                        }
                        try {
                          final bytes = File(imgPath).readAsBytesSync();
                          final mem = pw.MemoryImage(bytes);
                          return pw.Container(
                            width: thumbW,
                            height: thumbH,
                            margin: const pw.EdgeInsets.only(right: 6),
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(color: const pdf.PdfColor.fromInt(0xFFCCCCCC), width: 0.3),
                            ),
                            child: pw.FittedBox(fit: pw.BoxFit.cover, child: pw.Image(mem)),
                          );
                        } catch (_) {
                          return pw.Container(width: thumbW, height: thumbH);
                        }
                      }),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );

    final tmp = await getTemporaryDirectory();
    final file = File(p.join(tmp.path, '${_sanitize(title)}_${_ts()}.pdf'));
    await file.writeAsBytes(await doc.save(), flush: true);
    return file;
  }

  static String _ts() {
    final n = DateTime.now();
    String t(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${t(n.month)}${t(n.day)}_${t(n.hour)}${t(n.minute)}${t(n.second)}';
  }

  static String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[^\w\s.-]'), '').replaceAll(RegExp(r'\s+'), '_');
}
