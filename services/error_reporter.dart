// Simple facade para conectar Crashlytics, Sentry, etc.
// Por defecto: No-op (compila sin dependencias externas).

abstract class ErrorReporter {
  Future<void> recordError(Object error, StackTrace stack,
      {String? hint, Map<String, Object?>? extra});
  Future<void> log(String message, {Map<String, Object?>? extra});
}

class NoopErrorReporter implements ErrorReporter {
  const NoopErrorReporter();
  @override
  Future<void> recordError(Object error, StackTrace stack,
      {String? hint, Map<String, Object?>? extra}) async {}
  @override
  Future<void> log(String message, {Map<String, Object?>? extra}) async {}
}

// Punto ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Âºnico de acceso global
class ErrorReport {
  static ErrorReporter _instance = const NoopErrorReporter();
  static ErrorReporter get I => _instance;
  static set instance(ErrorReporter r) => _instance = r;
}

/* ---------- Ejemplos de implementaciÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³n (opcionales) ----------

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
class CrashlyticsReporter implements ErrorReporter {
  @override
  Future<void> recordError(Object error, StackTrace stack, {String? hint, Map<String, Object?>? extra}) {
    return FirebaseCrashlytics.instance.recordError(error, stack, reason: hint, information: [extra]);
  }
  @override
  Future<void> log(String message, {Map<String, Object?>? extra}) {
    FirebaseCrashlytics.instance.log('[Gridnote] $message ${extra ?? {}}');
    return Future.value();
  }
}

import 'package:sentry_flutter/sentry_flutter.dart';
class SentryReporter implements ErrorReporter {
  @override
  Future<void> recordError(Object error, StackTrace stack, {String? hint, Map<String, Object?>? extra}) {
    return Sentry.captureException(error, stackTrace: stack, hint: hint, withScope: (scope) {
      extra?.forEach((k, v) => scope.setExtra(k, '$v'));
    });
  }
  @override
  Future<void> log(String message, {Map<String, Object?>? extra}) {
    return Sentry.captureMessage('[Gridnote] $message ${extra ?? {}}');
  }
}
*/
