// lib/services/net.dart
import 'dart:async';
import 'dart:io' show InternetAddress, Socket, HttpClient;
import 'package:connectivity_plus/connectivity_plus.dart';

/// Tipo de red detectada.
enum NetworkKind { none, wifi, mobile, ethernet, vpn, other }

/// Snapshot rico de estado de red.
class NetworkStatus {
  final bool hasNetwork; // hay interfaz de red (plugin)
  final bool online;     // hay Internet “real” (deep-check)
  final NetworkKind kind;
  final ConnectivityResult raw;

  const NetworkStatus({
    required this.hasNetwork,
    required this.online,
    required this.kind,
    required this.raw,
  });

  @override
  String toString() =>
      'NetworkStatus(hasNetwork=$hasNetwork, online=$online, kind=$kind, raw=$raw)';
}

class Net {
  Net._();
  static final Net I = Net._();

  // ---------- Config ----------
  Duration _deepCheckTtl = const Duration(seconds: 5);
  Duration _deepCheckTimeout = const Duration(milliseconds: 900);
  Duration _emitThrottle = const Duration(milliseconds: 120);

  // Probes configurables
  final List<String> _dnsHosts = <String>[
    'one.one.one.one', // Cloudflare
    'google.com',
  ];
  final List<_HostPort> _socketProbes = <_HostPort>[
    const _HostPort('1.1.1.1', 53),
    const _HostPort('8.8.8.8', 53),
  ];
  final List<Uri> _httpProbes = <Uri>[
    Uri.parse('https://clients3.google.com/generate_204'),
    Uri.parse('https://www.gstatic.com/generate_204'),
    Uri.parse('https://httpstat.us/204'),
  ];

  // ---------- Estado ----------
  bool _hasNetwork = false; // del plugin
  bool _online = false;     // deep-check consolidado
  ConnectivityResult _lastRaw = ConnectivityResult.none;
  DateTime _lastDeepCheck = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  // ---------- Infra ----------
  final _onlineCtrl = StreamController<bool>.broadcast();
  final _statusCtrl = StreamController<NetworkStatus>.broadcast();
  StreamSubscription<dynamic>? _sub;
  Future<bool>? _inflight; // coalesce deep-checks
  bool _processing = false;

  // ---------- API pública ----------
  bool get online => _online;
  bool get hasNetwork => _hasNetwork;
  NetworkKind get kind => _mapKind(_lastRaw);

  Stream<bool> get onOnline => _onlineCtrl.stream.where((v) => v);
  Stream<NetworkStatus> get status$ => _statusCtrl.stream;

  NetworkStatus get currentStatus =>
      NetworkStatus(hasNetwork: _hasNetwork, online: _online, kind: kind, raw: _lastRaw);

  Future<void> init({
    Duration deepCheckTtl = const Duration(seconds: 5),
    Duration deepCheckTimeout = const Duration(milliseconds: 900),
    Duration emitThrottle = const Duration(milliseconds: 120),
    List<String>? dnsHosts,
    List<_HostPort>? socketProbes,
    List<Uri>? httpProbes,
  }) async {
    _deepCheckTtl = deepCheckTtl;
    _deepCheckTimeout = deepCheckTimeout;
    _emitThrottle = emitThrottle;

    if (dnsHosts != null && dnsHosts.isNotEmpty) {
      _dnsHosts
        ..clear()
        ..addAll(dnsHosts);
    }
    if (socketProbes != null && socketProbes.isNotEmpty) {
      _socketProbes
        ..clear()
        ..addAll(socketProbes);
    }
    if (httpProbes != null && httpProbes.isNotEmpty) {
      _httpProbes
        ..clear()
        ..addAll(httpProbes);
    }

    // Estado inicial
    _hasNetwork = await _probeConnectivity();
    _lastRaw = await _rawConnectivity();
    _online = _hasNetwork && await _deepCheck(force: true);
    _emit(); // emite snapshot inicial

    // Suscripción (maneja versiones del plugin que emiten list o single)
    await _sub?.cancel();
    _sub = Connectivity().onConnectivityChanged.listen((dynamic r) async {
      final list = _asList(r);
      final raw = list.isNotEmpty ? list.first : ConnectivityResult.none;
      final nowHasNet = list.any((e) => e != ConnectivityResult.none);
      if (nowHasNet != _hasNetwork || raw != _lastRaw) {
        _hasNetwork = nowHasNet;
        _lastRaw = raw;
        if (!_hasNetwork) {
          _setOnline(false);
        } else {
          unawaited(_refreshOnline()); // valida Internet con cache TTL
        }
      }
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _onlineCtrl.close();
    await _statusCtrl.close();
  }

  /// Revalida inmediatamente conectividad real (omite TTL).
  Future<bool> probeNow() async {
    await _refreshOnline(force: true);
    return _online;
  }

  /// ¿Internet real? (respeta TTL, hace deep-check si vencido).
  Future<bool> isOnline() async {
    if (!_hasNetwork) return false;
    await _refreshOnline();
    return _online;
  }

  /// Espera hasta estar online (true si logró dentro del timeout).
  Future<bool> waitForOnline({Duration timeout = const Duration(seconds: 30)}) async {
    if (await isOnline()) return true;
    final c = Completer<bool>();
    late StreamSubscription sub;
    Timer? timer;
    void done(bool v) {
      timer?.cancel();
      unawaited(sub.cancel());
      if (!c.isCompleted) c.complete(v);
    }
    sub = onOnline.listen((_) => done(true));
    timer = Timer(timeout, () => done(false));
    unawaited(_refreshOnline(force: true));
    return c.future;
  }

  /// Ejecuta [task] cuando haya Internet real; si no, espera hasta [timeout].
  Future<T> withOnline<T>(
      Future<T> Function() task, {
        Duration timeout = const Duration(seconds: 30),
      }) async {
    final ok = await waitForOnline(timeout: timeout);
    if (!ok) {
      throw StateError('Sin Internet (timeout ${timeout.inSeconds}s).');
    }
    return task();
  }

  // ---------- internos ----------
  Future<void> _refreshOnline({bool force = false}) async {
    if (_processing) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastDeepCheck) < _deepCheckTtl) return;

    _processing = true;
    try {
      _inflight ??= _deepCheck(force: force);
      final ok = await _inflight!;
      _setOnline(_hasNetwork && ok);
    } finally {
      _inflight = null;
      _processing = false;
    }
  }

  void _setOnline(bool v) {
    if (_online == v) {
      _emit(); // actualiza snapshot por cambio de tipo aunque online no cambie
      return;
    }
    _online = v;
    _emit();
    if (_online) _onlineCtrl.add(true);
  }

  void _emit() {
    final now = DateTime.now();
    if (now.difference(_lastEmit) < _emitThrottle) return;
    _lastEmit = now;
    _statusCtrl.add(currentStatus);
  }

  Future<bool> _deepCheck({bool force = false}) async {
    final now = DateTime.now();
    if (!force && now.difference(_lastDeepCheck) < _deepCheckTtl) return _online;
    _lastDeepCheck = now;

    // Jitter mínimo para evitar estampida cuando muchos esperan
    await Future<void>.delayed(Duration(milliseconds: 20 + (now.microsecond % 60)));

    // 1) HTTP 204 (mejor contra portales cautivos)
    for (final u in _httpProbes) {
      if (await _httpProbe(u)) return true;
    }

    // 2) DNS lookup (rápido, puede dar falsos positivos si hay portal)
    for (final h in _dnsHosts) {
      try {
        final res = await InternetAddress.lookup(h).timeout(_deepCheckTimeout);
        if (res.isNotEmpty && res.first.rawAddress.isNotEmpty) {
          // No devolvemos true todavía: confirmamos con socket
          break;
        }
      } catch (_) {}
    }

    // 3) Socket a DNS públicos (muy liviano)
    for (final hp in _socketProbes) {
      try {
        final s = await Socket.connect(hp.host, hp.port, timeout: _deepCheckTimeout);
        s.destroy();
        return true;
      } catch (_) {}
    }

    return false;
  }

  Future<bool> _httpProbe(Uri u) async {
    try {
      final client = HttpClient()..connectionTimeout = _deepCheckTimeout;
      client.maxConnectionsPerHost = 1;
      final req = await client.openUrl('HEAD', u).timeout(_deepCheckTimeout);
      req.followRedirects = false;
      final res = await req.close().timeout(_deepCheckTimeout);
      final ok = (res.statusCode == 204) || (res.statusCode >= 200 && res.statusCode < 300);
      client.close(force: true);
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _probeConnectivity() async {
    try {
      final r = await Connectivity().checkConnectivity();
      return _asList(r).any((e) => e != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  Future<ConnectivityResult> _rawConnectivity() async {
    try {
      final r = await Connectivity().checkConnectivity();
      final list = _asList(r);
      return list.isNotEmpty ? list.first : ConnectivityResult.none;
    } catch (_) {
      return ConnectivityResult.none;
    }
  }

  List<ConnectivityResult> _asList(dynamic r) {
    if (r is List<ConnectivityResult>) return r;
    if (r is ConnectivityResult) return <ConnectivityResult>[r];
    return const <ConnectivityResult>[ConnectivityResult.none];
  }

  NetworkKind _mapKind(ConnectivityResult r) {
    switch (r) {
      case ConnectivityResult.wifi:
        return NetworkKind.wifi;
      case ConnectivityResult.mobile:
        return NetworkKind.mobile;
      case ConnectivityResult.ethernet:
        return NetworkKind.ethernet;
      case ConnectivityResult.vpn:
        return NetworkKind.vpn;
      case ConnectivityResult.none:
        return NetworkKind.none;
      default:
        return NetworkKind.other;
    }
  }
}

class _HostPort {
  final String host;
  final int port;
  const _HostPort(this.host, this.port);
}
