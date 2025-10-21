// lib/config/app_support.dart
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

class AppSupport {
  static const email = 'soporte@bitacota.com'; // ← cambialo si hace falta

  static Uri mailto({String? subject, String? body}) => Uri(
    scheme: 'mailto',
    path: email,
    queryParameters: {
      if (subject != null) 'subject': subject,
      if (body != null) 'body': body,
    },
  );

  static Future<void> contact(BuildContext context,
      {String subject = 'Consulta Bitácora',
        String body = 'Hola, quisiera más info…'}) async {
    final uri = mailto(subject: subject, body: body);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      await Clipboard.setData(const ClipboardData(text: email));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay app de correo. Copiamos el email.')),
      );
    }
  }
}
