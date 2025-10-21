import 'dart:async';
import '../models/sheet.dart';

abstract class SheetsRepo {
  Future<List<Sheet>> listSheets();
  Future<int> newSheet(String name);
  Future<void> deleteSheet(int id);
  Future<void> renameSheet(int id, String newName);
}

class InMemorySheetsRepo implements SheetsRepo {
  final _items = <Sheet>[];
  int _auto = 1;

  @override
  Future<List<Sheet>> listSheets() async => List.unmodifiable(_items);

  @override
  Future<int> newSheet(String name) async {
    final id = _auto++;
    _items.add(Sheet(
      id: id,
      name: name,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    return id;
  }

  @override
  Future<void> deleteSheet(int id) async {
    _items.removeWhere((e) => e.id == id);
  }

  @override
  Future<void> renameSheet(int id, String newName) async {
    final i = _items.indexWhere((e) => e.id == id);
    if (i >= 0) _items[i] = _items[i].copyWith(name: newName);
  }
}
