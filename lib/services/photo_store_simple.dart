import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PhotoStoreSimple {
  PhotoStoreSimple._();
  static final _picker = ImagePicker();

  /// Toma foto con cámara, la guarda en /Documents/bitacora/photos/<sheetId>/<rowId>/ y devuelve el File.
  static Future<File?> addFromCamera({
    required String sheetId,
    required int rowId,
    double maxW = 800,
    double maxH = 800,
    int quality = 75,
  }) async {
    final shot = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: maxW,
      maxHeight: maxH,
      imageQuality: quality,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (shot == null) return null;

    final dir = await _dirFor(sheetId, rowId);
    final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final destPath = p.join(dir.path, name);

    // Guardamos *fuera* de /cache para evitar pérdidas.
    await shot.saveTo(destPath);
    return File(destPath);
  }

  /// Lista archivos guardados para esa fila.
  static Future<List<File>> list(String sheetId, int rowId) async {
    final dir = await _dirFor(sheetId, rowId);
    if (!await dir.exists()) return <File>[];
    final ents = await dir.list().toList();
    ents.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return ents.whereType<File>().toList();
  }

  static Future<Directory> _dirFor(String sheetId, int rowId) async {
    final docs = await getApplicationDocumentsDirectory();
    final d =
        Directory(p.join(docs.path, 'bitacora', 'photos', sheetId, '$rowId'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }
}
