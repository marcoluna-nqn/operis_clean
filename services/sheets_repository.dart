// lib/services/sheets_repository.dart
import '../models/sheet.dart';

abstract class SheetsRepository {
  Future<Sheet> createSheet({required String name});
  Future<List<Sheet>> listSheets();
  Stream<List<Sheet>> watchSheetsSorted();
  Future<void> deleteSheet(int id);
  Future<void> deleteSheetCascade(int id);
}
