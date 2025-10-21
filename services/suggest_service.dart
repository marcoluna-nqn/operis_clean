import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Sugerencias predictivas por columna (frecuencia + prefijo).
/// Persiste en SharedPreferences.
class SuggestService {
  static const _kKey = 'suggestions_v1';

  final Map<String, Map<String, int>> _freq = {}; // col -> (value -> count)

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kKey);
    if (raw == null) return;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    map.forEach((col, inner) {
      _freq[col] =
          (inner as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int));
    });
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kKey, jsonEncode(_freq));
  }

  void learn(String column, String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty) return;
    final m = _freq.putIfAbsent(column, () => {});
    m[v] = (m[v] ?? 0) + 1;
  }

  /// Retorna top-N que empiecen con `prefix` (case-insensitive).
  List<String> suggest(String column, String prefix, {int top = 6}) {
    final m = _freq[column];
    if (m == null || m.isEmpty) return const [];
    final low = prefix.toLowerCase();
    final all = m.entries
        .where((e) => e.key.toLowerCase().startsWith(low))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return all.take(top).map((e) => e.key).toList();
  }
}
