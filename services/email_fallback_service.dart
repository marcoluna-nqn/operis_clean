// lib/services/email_fallback_service.dart
// Envío con SharePlus (adjunta el XLSX). Fallback: mailto: sin adjunto.

import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class EmailFallbackService {
  const EmailFallbackService();

  Future<bool> sendFile({
    required File file,
    String subject = 'Planilla Bitácora',
    String body = 'Adjunto XLSX generado por Bitácora.',
    List<String> recipients = const [],
  }) async {
    // 1) SharePlus con adjunto (elegís Gmail/Outlook, etc.)
    try {
      await SharePlus.instance.share(
        ShareParams(
          subject: subject,
          text: body,
          files: [
            XFile(
              file.path,
              mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ),
          ],
        ),
      );
      return true;
    } catch (_) {
      // sigue al fallback
    }

    // 2) mailto: (no adjunta archivo; agregamos la ruta en el cuerpo)
    try {
      final uri = Uri(
        scheme: 'mailto',
        path: recipients.isNotEmpty ? recipients.join(',') : null,
        queryParameters: {
          'subject': subject,
          'body': '$body\n\nArchivo: ${file.path}',
        },
      );
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return true;
    } catch (_) {}

    return false;
  }
}
