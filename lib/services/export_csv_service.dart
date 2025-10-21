import 'dart:io' as io;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ExportCsvService {
  const ExportCsvService();

  Future<XFile> export({
    required List<String> headers,
    required List<List<String>> rows,
    required String fileName,
  }) async {
    final sb = StringBuffer();
    void writeRow(List<String> cols) => sb.writeln(cols.map(_csv).join(','));
    writeRow(headers);
    for (final r in rows) {
      writeRow(r);
    }

    final dir = await getTemporaryDirectory();
    final f = io.File(p.join(dir.path, '$fileName.csv'));
    await f.writeAsString(sb.toString(), flush: true);
    return XFile(f.path, name: p.basename(f.path), mimeType: 'text/csv');
  }

  String _csv(String s) {
    final t = (s ?? '').replaceAll('"','""');
    return '"$t"';
  }
}
