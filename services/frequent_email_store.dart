import 'package:shared_preferences/shared_preferences.dart';

class FrequentEmailStore {
  static const _kKey = 'gridnote_frequent_emails';
  static const _max = 5;

  Future<List<String>> getAll() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getStringList(_kKey) ?? <String>[];
  }

  Future<void> add(String email) async {
    final sp = await SharedPreferences.getInstance();
    final list = (sp.getStringList(_kKey) ?? <String>[]);
    list.removeWhere((e) => e.toLowerCase() == email.toLowerCase());
    list.insert(0, email);
    while (list.length > _max) {
      list.removeLast();
    }
    await sp.setStringList(_kKey, list);
  }
}
