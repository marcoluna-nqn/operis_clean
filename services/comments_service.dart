import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Comentarios por fila (persistencia ligera).
/// Clave: "comments::<sheetId>::<rowId>"
class CommentsService {
  static String _key(String sheetId, Object rowId) =>
      'comments::$sheetId::$rowId';

  Future<List<String>> getComments(String sheetId, Object rowId) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key(sheetId, rowId));
    if (raw == null) return const <String>[];
    return (jsonDecode(raw) as List).cast<String>();
  }

  Future<void> addComment(String sheetId, Object rowId, String comment) async {
    final sp = await SharedPreferences.getInstance();
    final k = _key(sheetId, rowId);
    final cur = await getComments(sheetId, rowId);
    final next = List<String>.from(cur)..add(comment);
    await sp.setString(k, jsonEncode(next));
  }
}
