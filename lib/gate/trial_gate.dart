import 'package:shared_preferences/shared_preferences.dart';


class TrialGate {
  static const _trialDays = 30;
  static const _trialStartKey = 'firstRunAt';


  Future<bool> isTrialActive() async {
    final prefs = await SharedPreferences.getInstance();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final first = prefs.getInt(_trialStartKey) ?? nowMs;
    if (!prefs.containsKey(_trialStartKey)) {
      await prefs.setInt(_trialStartKey, first);
    }
    final days = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(first))
        .inDays;
    return days < _trialDays;
  }


  Future<int> trialDaysLeft() async {
    final prefs = await SharedPreferences.getInstance();
    final first = prefs.getInt(_trialStartKey);
    if (first == null) return _trialDays;
    final used = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(first))
        .inDays;
    return (_trialDays - used).clamp(0, _trialDays);
  }


  Future<void> extendDays(int extraDays) async {
// Simple: movemos el "firstRunAt" hacia atrás para simular extensión
// (evita implementar un sistema de licencias complejo por ahora).
    final prefs = await SharedPreferences.getInstance();
    final first = prefs.getInt(_trialStartKey);
    if (first == null) return;
    final newFirst = DateTime.fromMillisecondsSinceEpoch(first)
        .subtract(Duration(days: extraDays))
        .millisecondsSinceEpoch;
    await prefs.setInt(_trialStartKey, newFirst);
  }
}
