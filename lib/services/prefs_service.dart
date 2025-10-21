import 'package:shared_preferences/shared_preferences.dart';

class PrefsService {
  static const _kLastXlsxPath = 'last_xlsx_path';
  static const _kGeotagEnabled = 'geotag_enabled';
  static const _kImageQuality = 'image_quality';
  static const _kWellPrefix = 'well_code_prefix';

  static Future<void> setLastXlsxPath(String path) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kLastXlsxPath, path);
  }

  static Future<String?> getLastXlsxPath() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_kLastXlsxPath);
  }

  static Future<void> setGeotagEnabled(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kGeotagEnabled, v);
  }

  static Future<bool> getGeotagEnabled() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kGeotagEnabled) ?? true;
  }

  static Future<void> setImageQuality(int q) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kImageQuality, q.clamp(50, 100));
  }

  static Future<int> getImageQuality() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt(_kImageQuality) ?? 92;
  }

  static Future<void> setWellPrefix(String s) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kWellPrefix, s);
  }

  static Future<String> getWellPrefix() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_kWellPrefix) ?? 'POZO';
  }
}
