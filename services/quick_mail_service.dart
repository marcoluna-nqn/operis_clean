// lib/services/quick_mail_service.dart
import 'package:share_plus/share_plus.dart';

import '../models/measurement.dart';
import '../models/sheet_meta.dart';
import 'export_xlsx_service.dart';

class QuickMailService {
  const QuickMailService();

  Future<void> sendSheet({
    required SheetMeta meta,
    required List<Measurement> rows,
    required String toEmail,
  }) async {
    final headers = <String>['Dato', 'Foto', 'Lat', 'Lng'];
    final data = rows.map((m) => <String>[m.toString(), '', '', '']).toList();

    final result = await ExportXlsxService.instance.exportToXlsx(
      headers: headers,
      rows: data,
      imagesByRow: const <int, List<String>>{},
      imageColumnIndex: 2,
      sheetName: meta.name.isEmpty ? 'Planilla' : meta.name,
    );

    await SharePlus.instance.share(
      ShareParams(
        files: [result.shareXFile],
        subject: 'Gridnote — ${meta.name}',
        text:
        'Adjunto XLSX generado para "${meta.name}". Sugerido enviar a: $toEmail',
      ),
    );
  }
}
