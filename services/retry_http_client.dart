// lib/services/retry_http_client.dart
//
// HTTP client con reintentos avanzados, backoff con jitter, soporte de Retry-After,
// cabeceras de trazabilidad (X-Request-Id, Idempotency-Key) y Circuit Breaker.
// Listo para producción.
//
// Requiere: package:http ^0.13 o ^1.0
//
// Uso:
// final client = RetryHttpClient();
// final res = await client.get(Uri.parse("https://api.example.com"));
// client.close();

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Políticas de backoff soportadas.
enum BackoffPolicy {
  /// Exponencial puro (sin jitter): base * 2^(attempt-1), cap en maxBackoff.
  exponential,

  /// Full Jitter (AWS): sleep = random(0, min(cap, base * 2^attempt)).
  fullJitter,

  /// Equal Jitter: sleep = min(cap, base * 2^attempt)/2 + random(0, min(cap, base * 2^attempt)/2).
  equalJitter,

  /// Decorrelated Jitter (aproximación stateless):
  /// random(min = base*(attempt-1), max = min(cap, base*2^attempt)).
  decorrelatedJitter,
}

/// Opciones de Circuit Breaker.
class CircuitBreakerOptions {
  /// Cantidad de fallos consecutivos para abrir el circuito.
  final int failureThreshold;

  /// Tiempo que permanece abierto el circuito (rechazando peticiones).
  final Duration openDuration;

  /// Máx. solicitudes de prueba en half-open (no estrictamente usado en esta versión).
  final int halfOpenMaxInFlight;

  const CircuitBreakerOptions({
    this.failureThreshold = 5,
    this.openDuration = const Duration(seconds: 30),
    this.halfOpenMaxInFlight = 1,
  });
}

/// Hooks opcionales para observabilidad.
class RetryHooks {
  final void Function(int attempt, http.BaseRequest req)? onAttemptStart;
  final void Function(
      int attempt,
      http.BaseRequest req,
      http.StreamedResponse resp,
      )? onAttemptResponse;
  final void Function(
      int attempt,
      http.BaseRequest req,
      Object error,
      StackTrace st,
      )? onAttemptError;
  final void Function(int attempt, Duration sleep)? onBackoff;
  final void Function(http.BaseRequest req, http.StreamedResponse resp)? onGiveUp;
  final void Function(http.BaseRequest req, http.StreamedResponse resp)? onSuccess;

  const RetryHooks({
    this.onAttemptStart,
    this.onAttemptResponse,
    this.onAttemptError,
    this.onBackoff,
    this.onGiveUp,
    this.onSuccess,
  });
}

/// Opciones del cliente de reintentos.
class RetryClientOptions {
  /// Reintentos máximos (no incluye el primer intento). Total intentos = maxRetries + 1.
  final int maxRetries;

  /// Delay base para backoff.
  final Duration baseDelay;

  /// Delay máximo (cap).
  final Duration maxBackoff;

  /// Política de backoff con jitter.
  final BackoffPolicy backoffPolicy;

  /// Respetar cabecera Retry-After si existe (HTTP 429/503).
  final bool respectRetryAfter;

  /// Métodos que se consideran reintentos por defecto (idempotentes).
  final Set<String> retryMethods;

  /// Códigos de respuesta que disparan reintento.
  final Set<int> retryStatusCodes;

  /// Timeout total de *cada intento* (no del flujo completo).
  final Duration? perAttemptTimeout;

  /// Añadir cabecera de trazabilidad.
  final bool addTraceIdHeader;

  /// Nombre de cabecera de trazabilidad.
  final String traceHeaderName;

  /// Generar automáticamente Idempotency-Key en métodos no-idempotentes (POST/PATCH/PUT) si falta.
  final bool generateIdempotencyKey;

  /// Nombre de cabecera de idempotencia.
  final String idempotencyHeaderName;

  /// Opciones del Circuit Breaker.
  final CircuitBreakerOptions circuitBreaker;

  /// Hooks opcionales.
  final RetryHooks hooks;

  const RetryClientOptions({
    this.maxRetries = 3,
    this.baseDelay = const Duration(milliseconds: 300),
    this.maxBackoff = const Duration(seconds: 30),
    this.backoffPolicy = BackoffPolicy.fullJitter,
    this.respectRetryAfter = true,
    this.retryMethods = const {'GET', 'HEAD', 'PUT', 'DELETE', 'OPTIONS'},
    this.retryStatusCodes = const {408, 425, 429, 500, 502, 503, 504},
    this.perAttemptTimeout,
    this.addTraceIdHeader = true,
    this.traceHeaderName = 'X-Request-Id',
    this.generateIdempotencyKey = true,
    this.idempotencyHeaderName = 'Idempotency-Key',
    this.circuitBreaker = const CircuitBreakerOptions(),
    this.hooks = const RetryHooks(),
  });
}

/// Estado simple de Circuit Breaker.
class _CircuitBreaker {
  final CircuitBreakerOptions _opts;
  int _consecutiveFailures = 0;
  DateTime? _openUntil;

  _CircuitBreaker(this._opts);

  bool get isOpen {
    final until = _openUntil;
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      // Half-open: dejamos pasar la próxima e intentamos cerrar si hay éxito.
      _openUntil = null;
      _consecutiveFailures = 0;
      return false;
    }
    return true;
  }

  void onSuccess() {
    _consecutiveFailures = 0;
    _openUntil = null;
  }

  void onFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= _opts.failureThreshold) {
      _openUntil = DateTime.now().add(_opts.openDuration);
    }
  }
}

/// Cliente HTTP con reintentos.
class RetryHttpClient extends http.BaseClient {
  final http.Client _inner;
  final RetryClientOptions _opts;
  final Random _rng = Random();
  final _CircuitBreaker _cb;

  RetryHttpClient({
    http.Client? inner,
    RetryClientOptions opts = const RetryClientOptions(),
  })  : _inner = inner ?? http.Client(),
        _opts = opts,
        _cb = _CircuitBreaker(opts.circuitBreaker);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final prepared = await _prepare(request);
    return _sendWithRetry(prepared);
  }

  @override
  void close() {
    _inner.close();
  }

  // -------- Core --------

  Future<http.StreamedResponse> _sendWithRetry(_Prepared prepared) async {
    if (_cb.isOpen) {
      throw StateError('Circuit breaker abierto: rechazando solicitudes temporalmente.');
    }

    final totalAttempts = _computeMaxAttempts(prepared);
    http.StreamedResponse? lastResp;
    Object? lastErr;
    StackTrace? lastSt;

    for (var attempt = 1; attempt <= totalAttempts; attempt++) {
      final req = await prepared.build();

      _opts.hooks.onAttemptStart?.call(attempt, req);

      try {
        final future = _inner.send(req);
        final resp = _opts.perAttemptTimeout != null
            ? await future.timeout(_opts.perAttemptTimeout!)
            : await future;

        _opts.hooks.onAttemptResponse?.call(attempt, req, resp);

        if (_shouldRetryResponse(req, resp)) {
          // Guardamos por si nos quedamos sin intentos.
          lastResp = resp;

          // Drenar el stream para liberar conexión antes del reintento.
          unawaited(resp.stream.drain().catchError((_) {}));

          // Elegir delay (Retry-After o backoff)
          final sleep = await _retryAfterOrBackoff(resp, attempt);
          if (attempt < totalAttempts) {
            _opts.hooks.onBackoff?.call(attempt, sleep);
            await Future.delayed(sleep);
            _cb.onFailure();
            continue;
          } else {
            _cb.onFailure();
            _opts.hooks.onGiveUp?.call(req, resp);
            return resp;
          }
        } else {
          // Éxito o no-retryable → devolvemos
          _cb.onSuccess();
          _opts.hooks.onSuccess?.call(req, resp);
          return resp;
        }
      } on TimeoutException catch (e, st) {
        lastErr = e;
        lastSt = st;
        _opts.hooks.onAttemptError?.call(attempt, req, e, st);
        if (attempt < totalAttempts) {
          final sleep = _backoffDelay(attempt, _opts);
          _opts.hooks.onBackoff?.call(attempt, sleep);
          await Future.delayed(sleep);
          _cb.onFailure();
          continue;
        } else {
          _cb.onFailure();
          rethrow;
        }
      } on SocketException catch (e, st) {
        lastErr = e;
        lastSt = st;
        _opts.hooks.onAttemptError?.call(attempt, req, e, st);
        if (attempt < totalAttempts) {
          final sleep = _backoffDelay(attempt, _opts);
          _opts.hooks.onBackoff?.call(attempt, sleep);
          await Future.delayed(sleep);
          _cb.onFailure();
          continue;
        } else {
          _cb.onFailure();
          rethrow;
        }
      } on HandshakeException catch (e, st) {
        lastErr = e;
        lastSt = st;
        _opts.hooks.onAttemptError?.call(attempt, req, e, st);
        if (attempt < totalAttempts) {
          final sleep = _backoffDelay(attempt, _opts);
          _opts.hooks.onBackoff?.call(attempt, sleep);
          await Future.delayed(sleep);
          _cb.onFailure();
          continue;
        } else {
          _cb.onFailure();
          rethrow;
        }
      } on http.ClientException catch (e, st) {
        lastErr = e;
        lastSt = st;
        _opts.hooks.onAttemptError?.call(attempt, req, e, st);
        if (attempt < totalAttempts) {
          final sleep = _backoffDelay(attempt, _opts);
          _opts.hooks.onBackoff?.call(attempt, sleep);
          await Future.delayed(sleep);
          _cb.onFailure();
          continue;
        } else {
          _cb.onFailure();
          rethrow;
        }
      }
    }

    // Si salimos del bucle (muy raro), devolvemos lo último que tengamos.
    if (lastResp != null) return lastResp;
    if (lastErr != null) Error.throwWithStackTrace(lastErr, lastSt!);
    throw StateError('RetryHttpClient: flujo de reintentos terminó inesperadamente.');
  }

  int _computeMaxAttempts(_Prepared p) {
    // Si el body no es reintetable (stream no clonable), hacemos un único intento.
    final canRetryBody = p.retryableBody;
    if (!canRetryBody) return 1;

    // Si el método no está en la lista de métodos retryables, dejamos 1 intento,
    // salvo que el servidor devuelva Retry-After (lo manejamos igual pero desde _shouldRetryResponse).
    final method = p.method.toUpperCase();
    if (!_opts.retryMethods.contains(method)) {
      // Permitimos reintentos para POST/PUT/PATCH solo si tienen Idempotency-Key o
      // el usuario habilitó generateIdempotencyKey.
      if (_isUnsafeMethod(method)) {
        final hasIdem = p.baseHeaders.containsKey(_opts.idempotencyHeaderName);
        final allow = hasIdem || _opts.generateIdempotencyKey;
        return allow ? (_opts.maxRetries + 1) : 1;
      }
      return 1;
    }

    return _opts.maxRetries + 1;
  }

  bool _isUnsafeMethod(String method) =>
      method == 'POST' || method == 'PUT' || method == 'PATCH';

  bool _shouldRetryResponse(http.BaseRequest req, http.StreamedResponse resp) {
    // Si status está en lista → reintento.
    if (_opts.retryStatusCodes.contains(resp.statusCode)) return true;

    // 5xx no listados explícitamente → opcionalmente se pueden considerar. Aquí no.
    return false;
  }

  Future<Duration> _retryAfterOrBackoff(http.StreamedResponse resp, int attempt) async {
    if (_opts.respectRetryAfter) {
      final ra = resp.headers.entries
          .firstWhere((e) => e.key.toLowerCase() == 'retry-after',
          orElse: () => const MapEntry('', ''))
          .value;
      if (ra.isNotEmpty) {
        final parsed = _parseRetryAfter(ra);
        if (parsed != null) {
          final ms = parsed.inMilliseconds
              .clamp(0, _opts.maxBackoff.inMilliseconds);
          return Duration(milliseconds: ms);
        }
      }
    }
    return _backoffDelay(attempt, _opts);
  }

  Duration _backoffDelay(int attempt, RetryClientOptions opts) {
    final baseMs = max(0, opts.baseDelay.inMilliseconds);
    final capMs = max(0, opts.maxBackoff.inMilliseconds);

    switch (opts.backoffPolicy) {
      case BackoffPolicy.exponential:
        final raw = (baseMs * pow(2, attempt - 1)).toInt();
        final ms = min(raw, capMs);
        return Duration(milliseconds: ms);

      case BackoffPolicy.fullJitter:
        final cap = min(capMs, (baseMs * pow(2, attempt)).toInt());
        final ms = _rng.nextInt(max(1, cap + 1));
        return Duration(milliseconds: ms);

      case BackoffPolicy.equalJitter:
        final cap = min(capMs, (baseMs * pow(2, attempt)).toInt());
        final half = (cap / 2).floor();
        final jitter = _rng.nextInt(max(1, cap - half + 1));
        final ms = half + jitter;
        return Duration(milliseconds: ms);

      case BackoffPolicy.decorrelatedJitter:
      // Aproximación stateless: rango que crece con el intento.
      // sleep ∈ [base*(attempt-1), min(cap, base*2^attempt)]
        final minFactor = max(1.0, attempt - 1.0);
        final maxFactor = pow(2, attempt).toDouble();
        final low = (baseMs * minFactor).toInt();
        final high = min(capMs, (baseMs * maxFactor).toInt());
        final span = max(1, high - low + 1);
        final ms = low + _rng.nextInt(span);
        return Duration(milliseconds: ms);
    }
  }

  Duration? _parseRetryAfter(String v) {
    final s = v.trim();
    if (s.isEmpty) return null;

    // "120" → segundos
    final secs = int.tryParse(s);
    if (secs != null) return Duration(seconds: secs);

    // HTTP-date
    try {
      final when = HttpDate.parse(s); // UTC
      final now = DateTime.now().toUtc();
      final diff = when.difference(now);
      return diff.isNegative ? Duration.zero : diff;
    } catch (_) {
      return null;
    }
  }

  // -------- Prepare (clonado seguro del request) --------

  Future<_Prepared> _prepare(http.BaseRequest original) async {
    final method = original.method.toUpperCase();
    final url = original.url;

    // Copia base de headers.
    final baseHeaders = <String, String>{};
    original.headers.forEach((k, v) {
      if (k.toLowerCase() != 'content-length') {
        baseHeaders[k] = v;
      }
    });

    // Trazabilidad / idempotencia (persisten entre intentos)
    _ensureTraceId(baseHeaders);
    _ensureIdempotencyKey(method, baseHeaders);

    // Soporte de http.Request con cuerpo / sin cuerpo.
    if (original is http.Request) {
      // Consumimos el stream una sola vez y guardamos bytes para reconstruir en cada intento.
      final bodyBytes = await http.ByteStream(original.finalize()).toBytes();
      final encodingName = original.encoding.name;
      final persistentHeaders = Map<String, String>.from(baseHeaders);

      Future<http.BaseRequest> builder() async {
        final req = http.Request(method, url);
        req.headers.addAll(persistentHeaders);
        // Si el usuario configuró content-type con charset, se respeta.
        if (bodyBytes.isNotEmpty) {
          req.bodyBytes = bodyBytes;
          // Restaurar encoding si aplica (http.Request usa encoding sólo al setear body String).
          if (encodingName.isNotEmpty &&
              !req.headers.containsKey(HttpHeaders.contentTypeHeader)) {
            req.headers[HttpHeaders.contentTypeHeader] =
            'text/plain; charset=$encodingName';
          }
        }
        return req;
      }

      return _Prepared(
        method: method,
        url: url,
        baseHeaders: persistentHeaders,
        retryableBody: true,
        build: builder,
      );
    }

    // Otros tipos (MultipartRequest, StreamedRequest, etc.): no garantizamos reintentos.
    // Enviaremos tal cual una sola vez (retryableBody=false).
    Future<http.BaseRequest> singleShot() async => original;

    return _Prepared(
      method: method,
      url: url,
      baseHeaders: baseHeaders,
      retryableBody: false,
      build: singleShot,
    );
  }

  void _ensureTraceId(Map<String, String> headers) {
    if (!_opts.addTraceIdHeader) return;
    final name = _opts.traceHeaderName;
    if (!headers.containsKey(name)) {
      headers[name] = _randomId();
    }
  }

  void _ensureIdempotencyKey(String method, Map<String, String> headers) {
    if (!_opts.generateIdempotencyKey) return;
    if (!_isUnsafeMethod(method)) return;
    final name = _opts.idempotencyHeaderName;
    headers.putIfAbsent(name, () => _randomId());
  }

  String _randomId([int bytes = 16]) {
    final b = List<int>.generate(bytes, (_) => _rng.nextInt(256));
    final sb = StringBuffer();
    for (final v in b) {
      sb.write(v.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

class _Prepared {
  final String method;
  final Uri url;
  final Map<String, String> baseHeaders;
  final bool retryableBody;
  final Future<http.BaseRequest> Function() build;

  _Prepared({
    required this.method,
    required this.url,
    required this.baseHeaders,
    required this.retryableBody,
    required this.build,
  });
}
