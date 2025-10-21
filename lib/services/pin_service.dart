import 'package:shared_preferences/shared_preferences.dart';

class PinService {
  static const _kPin = 'app_pin';
  static const _kLocked = 'app_locked';

  static Future<bool> hasPin() async {
    final p = await SharedPreferences.getInstance();
    return (p.getString(_kPin) ?? '').isNotEmpty;
  }

  static Future<void> setPin(String pin) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPin, pin);
  }

  static Future<bool> verify(String pin) async {
    final p = await SharedPreferences.getInstance();
    return (p.getString(_kPin) ?? '') == pin;
  }

  static Future<void> setLocked(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kLocked, v);
  }

  static Future<bool> isLocked() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kLocked) ?? false;
  }
}
