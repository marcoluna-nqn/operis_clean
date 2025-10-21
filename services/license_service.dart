// lib/services/license_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class LicenseState {
  final DateTime? validUntil;   // cuándo vence
  final String status;          // 'active' | 'suspended' | 'expired'
  final DateTime lastChecked;   // última verificación
  final String? message;        // msg opcional del backend

  const LicenseState({
    required this.validUntil,
    required this.status,
    required this.lastChecked,
    this.message,
  });

  bool get isActive => status == 'active';
  bool get isExpired => validUntil != null && DateTime.now().isAfter(validUntil!);

  // Permite 72h de gracia si no hay internet y la última licencia fue válida.
  bool isCurrentlyValid({Duration offlineGrace = const Duration(hours: 72)}) {
    if (isActive && !isExpired) return true;
    if (isActive &&
        isExpired &&
        DateTime.now().isBefore((validUntil ?? DateTime.fromMillisecondsSinceEpoch(0)).add(offlineGrace))) {
      return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
    'valid_until': validUntil?.toUtc().toIso8601String(),
    'status': status,
    'last_checked': lastChecked.toUtc().toIso8601String(),
    'message': message,
  };

  static LicenseState fromJson(Map<String, dynamic> j) => LicenseState(
    validUntil: j['valid_until'] == null
        ? null
        : DateTime.tryParse(j['valid_until'] as String)?.toLocal(),
    status: (j['status'] ?? 'expired') as String,
    lastChecked: DateTime.tryParse(j['last_checked'] as String? ?? '')?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0),
    message: j['message'] as String?,
  );

  static LicenseState initial() => LicenseState(
    validUntil: null,
    status: 'expired',
    lastChecked: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

class LicenseService {
  LicenseService._();
  static final LicenseService instance = LicenseService._();

  final ValueNotifier<LicenseState> _state =
  ValueNotifier<LicenseState>(LicenseState.initial());
  ValueListenable<LicenseState> get listenable => _state;

  late final String installId;
  String? _appVersion;
  Timer? _periodic;
  Duration _autoEvery = const Duration(hours: 6);

  // ====== INIT ======
  Future<void> init({String? appVersion, Duration autoCheckEvery = const Duration(hours: 6)}) async {
    _appVersion = appVersion;
    _autoEvery = autoCheckEvery;
    installId = await _loadOrCreateInstallId();
    final cached = await _loadCachedState();
    if (cached != null) _state.value = cached;

    // Verificación inicial (no bloqueante)
    unawaited(_checkNow(remotePreferred: true));

    _periodic?.cancel();
    _periodic = Timer.periodic(_autoEvery, (_) => _checkNow(remotePreferred: true));
  }

  // ====== GATE WIDGET ======
  Widget gate({required Widget child, String? manageUrl}) {
    return ValueListenableBuilder<LicenseState>(
      valueListenable: _state,
      builder: (ctx, st, _) {
        final blocked = !st.isCurrentlyValid();
        return Stack(children: [
          child,
          if (blocked)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.65),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Card(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lock_outline, size: 42),
                            const SizedBox(height: 8),
                            Text('Licencia requerida', style: Theme.of(ctx).textTheme.titleLarge),
                            const SizedBox(height: 8),
                            Text(
                              st.message ??
                                  (st.status == 'suspended'
                                      ? 'Tu licencia está suspendida.'
                                      : st.validUntil == null
                                      ? 'No se encontró una licencia válida.'
                                      : 'La licencia venció.'),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            if (st.validUntil != null)
                              Text(
                                'Vencimiento: ${_fmt(st.validUntil!)}',
                                style: Theme.of(ctx).textTheme.bodySmall,
                              ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Reintentar'),
                                    onPressed: () => _checkNow(remotePreferred: true),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton.icon(
                                    icon: const Icon(Icons.open_in_new),
                                    label: const Text('Gestionar'),
                                    onPressed: manageUrl == null
                                        ? null
                                        : () async {
                                      final uri = Uri.parse(manageUrl);
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            TextButton(
                              onPressed: () => _checkNow(remotePreferred: false),
                              child: const Text('Usar caché (si hay)'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]);
      },
    );
  }

  // ====== PUBLIC ======
  Future<void> checkNow() => _checkNow(remotePreferred: true);

  // ====== CORE ======
  Future<void> _checkNow({required bool remotePreferred}) async {
    try {
      final conn = await Connectivity().checkConnectivity();
      final bool online = (conn is List<ConnectivityResult>)
          ? conn.any((e) =>
      e == ConnectivityResult.mobile ||
          e == ConnectivityResult.wifi ||
          e == ConnectivityResult.ethernet)
          : (conn == ConnectivityResult.mobile ||
          conn == ConnectivityResult.wifi   ||
          conn == ConnectivityResult.ethernet);

      if (remotePreferred && online) {
        final fresh = await _fetchRemote();
        _state.value = fresh;
        await _saveCachedState(fresh);
        return;
      }

      final cached = await _loadCachedState() ?? LicenseState.initial();
      _state.value = cached;
    } catch (_) {
      // mantener estado actual
    }
  }

  Future<LicenseState> _fetchRemote() async {
    final callable = FirebaseFunctions.instance.httpsCallable('checkLicense');
    final res = await callable.call(<String, dynamic>{
      'installId': installId,
      'version': _appVersion ?? 'unknown',
    });
    final data = Map<String, dynamic>.from(res.data as Map);

    final status = (data['status'] ?? 'expired') as String;
    final validUntilStr = data['validUntil'] as String?;
    final msg = data['message'] as String?;
    final validUntil = validUntilStr == null ? null : DateTime.tryParse(validUntilStr)?.toLocal();

    return LicenseState(
      validUntil: validUntil,
      status: status,
      lastChecked: DateTime.now(),
      message: msg,
    );
  }

  // ====== STORAGE ======
  Future<String> _loadOrCreateInstallId() async {
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/install_id.txt');
    if (await f.exists()) {
      final v = (await f.readAsString()).trim();
      if (v.isNotEmpty) return v;
    }
    final rnd = Random.secure();
    String randHex(int n) => List<int>.generate(n, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final id = 'and_${DateTime.now().millisecondsSinceEpoch}_${randHex(8)}';
    await f.writeAsString(id, flush: true);
    return id;
  }

  Future<LicenseState?> _loadCachedState() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/license_state.json');
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return LicenseState.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCachedState(LicenseState st) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/license_state.json');
      await f.writeAsString(jsonEncode(st.toJson()), flush: true);
    } catch (_) {}
  }
}

// ===== helpers
String _fmt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
