import '../licensing/license_manager.dart';

class PhotoLimit {
  static int get maxPerSheet {
    final l = LicenseManager.instance.state;
    switch (l.status) {
      case LicenseStatus.valid:
        return 50;
      case LicenseStatus.trial:
        return 5;
      case LicenseStatus.expired:
      case LicenseStatus.invalid:
        return 0;
    }
  }

  static bool canAdd(int currentCount) =>
      maxPerSheet < 0 || currentCount < maxPerSheet;

  static int remaining(int currentCount) =>
      maxPerSheet < 0 ? 1 << 30 : (maxPerSheet - currentCount).clamp(0, 1 << 30);

  static String blockMessage() => maxPerSheet == 0
      ? 'Tu licencia expiró. Renová para adjuntar fotos.'
      : 'Límite de $maxPerSheet fotos por planilla en la demo.';

  static String badgeText(int currentCount) =>
      maxPerSheet < 0 ? '$currentCount' : '$currentCount/$maxPerSheet';
}
