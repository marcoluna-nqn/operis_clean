// lib/services/share_or_queue.dart
import 'package:share_plus/share_plus.dart';
import 'net_service.dart';
import 'pending_share_store.dart';

class SafeShare {
  static Future<void> shareOrQueue(List<XFile> files,
      {required String subject, String? text}) async {
    final online = await Net.I.isOnline();
    if (online) {
      final res = await SharePlus.instance
          .share(ShareParams(files: files, subject: subject, text: text));
      if (res.status == ShareResultStatus.success) return;
      // Si el usuario cancela, no encolamos (evita spam no deseado).
      return;
    } else {
      await PendingShareStore.I.enqueueFiles(files, subject: subject, text: text);
    }
  }
}
