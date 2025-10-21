import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/app_db.dart';
import 'repositories/sheets_repository.dart';

final dbProvider = Provider<AppDb>((ref) => AppDb());
final repoProvider =
    Provider<SheetsRepo>((ref) => SheetsRepo(ref.read(dbProvider)));

final sheetProvider =
    AsyncNotifierProvider<SheetController, SheetData?>(SheetController.new);

class SheetController extends AsyncNotifier<SheetData?> {
  SheetsRepo get _repo => ref.read(repoProvider);

  @override
  Future<SheetData?> build() async {
    return _repo.initIfNeeded(columns: 5);
  }

  Future<void> refresh() async => state = await AsyncValue.guard(_repo.get);

  Future<void> updateHeaders(List<String> headers) async {
    await _repo.setHeaders(headers);
    await refresh();
  }

  Future<void> updateCell(int rowIndex, int col, String value) async {
    final s = state.value;
    if (s == null) return;
    final r = s.rows[rowIndex];
    final newCells = List<String>.from(r.cells)..[col] = value;
    final upd = RowData(
      id: r.id,
      index: r.index,
      cells: newCells,
      photos: List.from(r.photos),
      lat: r.lat,
      lng: r.lng,
      placeName: r.placeName,
    );
    await _repo.saveRow(upd);
    await refresh();
  }

  Future<void> setLocation(int rowIndex,
      {double? lat, double? lng, String? name}) async {
    final s = state.value;
    if (s == null) return;
    final r = s.rows[rowIndex];
    final upd = RowData(
      id: r.id,
      index: r.index,
      cells: List.from(r.cells),
      photos: List.from(r.photos),
      lat: lat ?? r.lat,
      lng: lng ?? r.lng,
      placeName: name ?? r.placeName,
    );
    await _repo.saveRow(upd);
    await refresh();
  }

  Future<void> addPhotos(int rowIndex, List<String> paths) async {
    final s = state.value;
    if (s == null) return;
    final r = s.rows[rowIndex];
    final upd = RowData(
      id: r.id,
      index: r.index,
      cells: List.from(r.cells),
      photos: [...r.photos, ...paths],
      lat: r.lat,
      lng: r.lng,
      placeName: r.placeName,
    );
    await _repo.saveRow(upd);
    await refresh();
  }

  Future<void> deleteRow(int rowIndex) async {
    final s = state.value;
    if (s == null) return;
    await _repo.removeRow(s.rows[rowIndex]);
    await refresh();
  }

  Future<void> addRow() async {
    final s = state.value;
    if (s == null) return;
    final cells = List.filled(s.columns, '');
    await _repo.addRow(cells, s.rows.length);
    await refresh();
  }
}
