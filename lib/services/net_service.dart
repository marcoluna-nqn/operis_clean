// lib/services/net_service.dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class Net {
  Net._();
  static final Net I = Net._();

  final _onlineCtrl = StreamController<bool>.broadcast();
  Stream<bool> get onOnline => _onlineCtrl.stream.where((v) => v);

  StreamSubscription<dynamic>? _sub;
  bool _online = true;
  bool get online => _online;

  Future<void> init() async {
    _online = await isOnline();
    await _sub?.cancel();
    _sub = Connectivity().onConnectivityChanged.listen((dynamic r) {
      bool nowOnline = _online;
      if (r is List<ConnectivityResult>) {
        nowOnline = r.any((e) => e != ConnectivityResult.none);
      } else if (r is ConnectivityResult) {
        nowOnline = r != ConnectivityResult.none;
      }
      if (nowOnline != _online) {
        _online = nowOnline;
        _onlineCtrl.add(_online);
      }
    });
  }

  Future<bool> isOnline() async {
    final r = await Connectivity().checkConnectivity();
    return r != ConnectivityResult.none;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _onlineCtrl.close();
  }
}
