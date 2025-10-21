import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Servicio de Onboarding con:
/// - Cache en memoria (sin jank)
/// - Versionado (reinicia onboarding cuando cambie la versión que definas)
/// - Marca de tiempo del “visto”
/// - Listenable para reaccionar en UI
///
/// Uso típico (en main()):
///   await OnboardingService.I.init(version: 2);
///   if (!OnboardingService.I.done) { /* mostrar onboarding */ }
class OnboardingService {
  OnboardingService._();
  static final OnboardingService I = OnboardingService._();

  // Claves (no cambies estos strings una vez en producción)
  static const _kDoneKey = 'onboarding.done';
  static const _kVersionKey = 'onboarding.version';
  static const _kSeenAtKey = 'onboarding.seen_at_ms';

  SharedPreferences? _prefs;

  bool _initialized = false;
  int _currentVersion = 1;

  bool _done = false;
  int? _seenAtMs;

  /// Listenable para que tu UI se actualice si cambia el estado.
  final ValueNotifier<bool> doneListenable = ValueNotifier<bool>(false);

  /// Llamar una vez al inicio de la app.
  Future<void> init({required int version}) async {
    if (_initialized && _currentVersion == version) return;

    _prefs ??= await SharedPreferences.getInstance();
    _currentVersion = version;

    final storedVersion = _prefs!.getInt(_kVersionKey);
    // Si la versión cambió, “reseteamos” el onboarding.
    if (storedVersion == null || storedVersion != version) {
      await _prefs!.setInt(_kVersionKey, version);
      await _prefs!.remove(_kDoneKey);
      await _prefs!.remove(_kSeenAtKey);
      _done = false;
      _seenAtMs = null;
    } else {
      _done = _prefs!.getBool(_kDoneKey) ?? false;
      _seenAtMs = _prefs!.getInt(_kSeenAtKey);
    }

    doneListenable.value = _done;
    _initialized = true;
  }

  bool get isInitialized => _initialized;

  /// Estado actual (sin await gracias a la cache).
  bool get done {
    _debugAssertInitialized();
    return _done;
  }

  /// Fecha/hora (local) en que se marcó como hecho, o null.
  DateTime? get seenAt {
    _debugAssertInitialized();
    return _seenAtMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(_seenAtMs!);
  }

  /// Marca el onboarding como completado (idempotente).
  Future<bool> markDone() async {
    _debugAssertInitialized();
    if (_done) return true;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final okDone = await _prefs!.setBool(_kDoneKey, true);
    final okTime = await _prefs!.setInt(_kSeenAtKey, nowMs);

    final ok = okDone && okTime;
    if (ok) {
      _done = true;
      _seenAtMs = nowMs;
      doneListenable.value = true;
    }
    return ok;
  }

  /// Útil para pruebas o si querés repetir el onboarding.
  Future<void> reset() async {
    _debugAssertInitialized();
    await _prefs!.remove(_kDoneKey);
    await _prefs!.remove(_kSeenAtKey);
    _done = false;
    _seenAtMs = null;
    doneListenable.value = false;
  }

  /// Fuerza a persistir un valor arbitrario (ej. “Saltar”/“Recordar más tarde”).
  Future<void> setDone(bool value) async {
    _debugAssertInitialized();
    _done = value;
    doneListenable.value = value;
    await _prefs!.setBool(_kDoneKey, value);
    if (value) {
      _seenAtMs = DateTime.now().millisecondsSinceEpoch;
      await _prefs!.setInt(_kSeenAtKey, _seenAtMs!);
    } else {
      _seenAtMs = null;
      await _prefs!.remove(_kSeenAtKey);
    }
  }

  void _debugAssertInitialized() {
    assert(
    _initialized,
    'OnboardingService no inicializado. Llamá a OnboardingService.I.init(version: X) en el arranque.',
    );
  }
}
