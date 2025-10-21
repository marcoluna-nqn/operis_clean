import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class MediaPaths {
  MediaPaths._();
  static Future<Directory> _appDir() async =>
      await getApplicationDocumentsDirectory();

  static Future<Directory> tmpDir() async {
    final d = Directory(p.join((await _appDir()).path, 'tmp'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<Directory> mediaDir() async {
    final d = Directory(p.join((await _appDir()).path, 'media'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<File> tmpFile(String name) async =>
      File(p.join((await tmpDir()).path, name));
  static Future<File> mediaFile(String name) async =>
      File(p.join((await mediaDir()).path, name));
  static Future<File> queueFile() async =>
      File(p.join((await _appDir()).path, 'upload_queue.json'));
}
