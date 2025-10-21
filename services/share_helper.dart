// lib/services/share_helper.dart
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;

Future<void> shareXlsx(File xlsx) async {
  final name = p.basename(xlsx.path);
  await SharePlus.instance.share(
    ShareParams(
      text: 'Exportado: $name',
      subject: 'Bitácora – $name',
      files: [
        XFile(
          xlsx.path,
          mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          name: name,
        ),
      ],
    ),
  );
}
