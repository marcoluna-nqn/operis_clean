// lib/services/connectivity_service.dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService I = ConnectivityService._();

  final _controller = StreamController<bool>.broadcast();
  bool _last = true;

  Stream<bool> get onChanged => _controller.stream;

  Future<void> init() async {
    final c = await Connectivity().checkConnectivity();
    _last = _isUp(c);
    Connectivity().onConnectivityChanged.listen((changes) {
      final up = _isUp(changes);
      if (up != _last) {
        _last = up;
        _controller.add(up);
      }
    });
  }

  Future<bool> isOnline() async {
    final c = await Connectivity().checkConnectivity();
    return _isUp(c);
  }

  bool _isUp(List<ConnectivityResult> list) =>
      list.any((e) => e == ConnectivityResult.mobile || e == ConnectivityResult.wifi || e == ConnectivityResult.ethernet);
}
