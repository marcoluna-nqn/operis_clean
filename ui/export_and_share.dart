// lib/ui/export_and_share.dart
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../services/export_xlsx_service.dart';

Future<void> exportAndShare(
    BuildContext context, {
      required List<String> headers,
      required List<List<String>> rows,
      required Map<int, List<String>> imagesByRow,
      required int imageColumnIndex,
      required String sheetName,
    }) async {
  final res = await ExportXlsxService.instance.exportToXlsx(
    headers: headers,
    rows: rows,
    imagesByRow: imagesByRow,
    imageColumnIndex: imageColumnIndex,
    sheetName: sheetName,
  );

  final fullPath = res.xlsxFile.path;
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exportado: $fullPath')),
    );
  }

  try {
    await SharePlus.instance.share(
      ShareParams(
        subject: 'Bitácora – Exportación',
        text: 'Planilla exportada desde Bitácora',
        files: [res.shareXFile],
      ),
    );
    return;
  } catch (_) {}

  final r = await OpenFilex.open(
    res.xlsxFile.path,
    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  );
  if (context.mounted && r.type != ResultType.done) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo compartir/abrir el archivo')),
    );
  }
}
