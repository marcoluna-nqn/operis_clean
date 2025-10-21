// lib/services/email_share_service.dart
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class EmailShareService {
  const EmailShareService();

  /// Comparte el archivo por el “share sheet” del sistema.
  /// Si el usuario no elige una app de correo, se intenta abrir un mailto:
  /// (mailto no soporta adjuntos).
  Future<void> sendWithFallback({
    required String to,
    required String subject,
    required String body,
    required File attachment,
  }) async {
    // 1) Share sheet con adjunto
    try {
      await Share.shareXFiles(
        [
          XFile(
            attachment.path,
            mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
        subject: subject,
        text: body,
      );
      return;
    } catch (_) {
      // sigue al mailto
    }

    // 2) Fallback: mailto (sin adjunto)
    final uri = Uri(
      scheme: 'mailto',
      path: to,
      queryParameters: <String, String>{
        'subject': subject,
        'body': body,
      },
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
