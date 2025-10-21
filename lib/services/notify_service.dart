// lib/services/notify_service.dart
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_filex/open_filex.dart';

class NotifyService {
  static final NotifyService I = NotifyService._();
  NotifyService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _inited = false;

  DateTime _lastSaved = DateTime.fromMillisecondsSinceEpoch(0);

  // ===== Canales =====
  static const _saveId = 'save_channel';
  static const _saveName = 'Guardados';
  static const _saveDesc = 'Notificaciones de guardado local/auto';

  static const _exportId = 'export_channel';
  static const _exportName = 'Exportaciones';
  static const _exportDesc = 'Archivos XLSX generados por la app';

  // ===== Init =====
  Future<void> init() async {
    if (_inited) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const init = InitializationSettings(android: androidInit, iOS: iosInit);

    await _plugin.initialize(
      init,
      onDidReceiveNotificationResponse: (resp) async {
        final payload = resp.payload ?? '';
        if (payload.startsWith('open:')) {
          final path = payload.substring('open:'.length);
          await OpenFilex.open(path);
        }
      },
    );

    final android =
    _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(const AndroidNotificationChannel(
        _saveId,
        _saveName,
        description: _saveDesc,
        importance: Importance.defaultImportance,
      ));
      await android.createNotificationChannel(const AndroidNotificationChannel(
        _exportId,
        _exportName,
        description: _exportDesc,
        importance: Importance.high,
      ));
      await android.requestNotificationsPermission();
    }

    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _inited = true;
  }

  /// Notificación liviana de autosave (con throttle).
  Future<void> savedOk(String title) async {
    if (!_inited) await init();

    final now = DateTime.now();
    if (now.difference(_lastSaved).inSeconds < 5) return; // throttle
    _lastSaved = now;

    const android = AndroidNotificationDetails(
      _saveId,
      _saveName,
      channelDescription: _saveDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      styleInformation: BigTextStyleInformation(''),
      category: AndroidNotificationCategory.status,
    );
    const ios = DarwinNotificationDetails();

    await _plugin.show(
      10, // id fijo para estado de guardado
      'Datos guardados',
      title,
      const NotificationDetails(android: android, iOS: ios),
    );
  }

  /// Notificación de exportación con "tocar para abrir" el archivo.
  Future<void> savedXlsx(String title, String path) async {
    if (!_inited) await init();

    const android = AndroidNotificationDetails(
      _exportId,
      _exportName,
      channelDescription: _exportDesc,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
      category: AndroidNotificationCategory.status,
      visibility: NotificationVisibility.public,
    );
    const ios = DarwinNotificationDetails();

    // id único por archivo para no pisar notificaciones anteriores
    final nid = 11 + (path.hashCode & 0x7fffffff);

    await _plugin.show(
      nid,
      'Exportación lista: $title',
      'Se guardó en:\n$path\n\nTocá para abrir.',
      const NotificationDetails(android: android, iOS: ios),
      payload: 'open:$path',
    );
  }
}
