import 'package:shared_preferences/shared_preferences.dart';


/// Gate de "licencia" ultra simple para hoy.
/// Si encontrás `license_expires_ms > now`, está habilitado.
class EntitlementGate {
  static const _expiresKey = 'license_expires_ms';


  Future<bool> hasEntitlement() async {
    final prefs = await SharedPreferences.getInstance();
    final exp = prefs.getInt(_expiresKey) ?? 0;
    return DateTime.now().millisecondsSinceEpoch < exp;
  }


  /// Otorga una licencia temporal `days` días desde ahora.
  Future<void> grantDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    final exp = DateTime.now().add(Duration(days: days)).millisecondsSinceEpoch;
    await prefs.setInt(_expiresKey, exp);
  }


  Future<DateTime?> entitlementExpiry() async {
    final prefs = await SharedPreferences.getInstance();
    final exp = prefs.getInt(_expiresKey);
    if (exp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(exp);
  }
}
