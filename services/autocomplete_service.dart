import 'package:shared_preferences/shared_preferences.dart';

/// Autocompletado muy simple de observaciones (persistido en prefs).
class AutocompleteService {
  AutocompleteService._();
  static final AutocompleteService instance = AutocompleteService._();

  static const _kObs = 'gridnote_obs_suggestions_v1';

  Future<List<String>> suggestions({String q = ''}) async {
    final p = await SharedPreferences.getInstance();
    final all = p.getStringList(_kObs) ?? const <String>[];
    if (q.trim().isEmpty) return all.reversed.toList();
    final lower = q.toLowerCase();
    return all
        .where((e) => e.toLowerCase().contains(lower))
        .toList()
        .reversed
        .toList();
  }

  Future<void> addObservation(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    final set = (p.getStringList(_kObs) ?? const <String>[]).toSet();
    set.add(t);
    await p.setStringList(_kObs, set.toList());
  }
}
