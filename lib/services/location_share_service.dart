// lib/services/location_share_service.dart
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class LocationShareService {
  /// Enlace a Google Maps con zoom razonable.
  static String mapsUrl(double lat, double lng, {String? label}) {
    final qLabel = (label == null || label.trim().isEmpty)
        ? '$lat,$lng'
        : '${Uri.encodeComponent(label)}@$lat,$lng';
    // q: muestra pin; ll: centra; z: zoom
    return 'https://maps.google.com/?q=$qLabel&ll=$lat,$lng&z=17';
    // Alternativa muy fiable:
    // return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
  }

  static Future<void> share(String label, double lat, double lng) async {
    final url = mapsUrl(lat, lng, label: label);
    final text = (label.trim().isEmpty) ? url : '$label\n$url';
    await Share.share(
      text,
      subject: label.isEmpty ? 'Ubicación' : label,
    );
  }

  /// “Email” sin plugin nativo: abre el cliente de correo con mailto:.
  /// Si no hay handler, cae a compartir.
  static Future<void> email(
      String to,
      String label,
      double lat,
      double lng,
      ) async {
    final url = mapsUrl(lat, lng, label: label);
    final subject = label.isEmpty ? 'Ubicación' : 'Ubicación: $label';
    final body = (label.trim().isEmpty) ? url : '$label\n\n$url';

    final mailto = Uri(
      scheme: 'mailto',
      path: to,
      queryParameters: {
        'subject': subject,
        'body': body,
      },
    );

    if (await canLaunchUrl(mailto)) {
      await launchUrl(mailto, mode: LaunchMode.externalApplication);
    } else {
      // Fallback a compartir si no hay cliente de email
      await Share.share(body, subject: subject);
    }
  }
}
