// lib/services/free_sheet_service.dart
import '../repositories/sheets_repo.dart';

class FreeSheetService {
  final SheetsRepo repo;
  FreeSheetService(this.repo);

  Future<int> createQuickSheet() => repo.newSheet('Planilla rápida');
}
