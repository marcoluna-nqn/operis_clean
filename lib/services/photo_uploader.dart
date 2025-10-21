// lib/services/photo_uploader.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Resultado uniforme para la subida de fotos.
class UploadResult {
  final bool ok;
  final String? url;
  final String? serverHash;
  final int status; // HTTP status o 408 para timeout / 0 para errores locales
  final String? error;

  const UploadResult({
    required this.ok,
    this.url,
    this.serverHash,
    required this.status,
    this.error,
  });
}

/// Contrato para adaptadores de subida.
abstract class PhotoUploader {
  Future<UploadResult> upload({
    required File file,
    required String sha256hex,
    Duration timeout = const Duration(seconds: 30),
  });
}

/// Implementación HTTP robusta (streaming + headers de trazabilidad).
class HttpPhotoUploader implements PhotoUploader {
  HttpPhotoUploader({
    required this.endpoint,
    Map<String, String>? headers,
    http.Client? client,
    String Function()? requestIdFactory,
  })  : _baseHeaders = Map.unmodifiable(headers ?? const {}),
        _http = client ?? http.Client(),
        _requestIdFactory = requestIdFactory ?? _defaultRequestId;

  final Uri endpoint;
  final Map<String, String> _baseHeaders;
  final http.Client _http;
  final String Function() _requestIdFactory;

  @override
  Future<UploadResult> upload({
    required File file,
    required String sha256hex,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final req = http.MultipartRequest('POST', endpoint);

    // Trazabilidad e idempotencia
    final reqId = _requestIdFactory();
    final idemKey = _idempotencyKeyFor(sha256hex);

    req.headers.addAll(_baseHeaders);
    req.headers.putIfAbsent('X-Request-Id', () => reqId);
    req.headers.putIfAbsent('Idempotency-Key', () => idemKey);
    req.headers.putIfAbsent('X-Checksum-SHA256', () => sha256hex);

    req.fields['sha256'] = sha256hex;

    // Archivo en streaming
    final length = await file.length();
    final stream = http.ByteStream(file.openRead());
    final filename =
    file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'upload.bin';
    req.files.add(http.MultipartFile('file', stream, length, filename: filename));

    try {
      // ✅ Timeout aplicado al FUTURE entero (send + leer respuesta)
      final res = await (() async {
        final streamed = await _http.send(req);
        return http.Response.fromStream(streamed);
      })().timeout(timeout);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final map = _tryJsonMap(res.body);
        final url = map?['url']?.toString() ??
            _firstNonEmptyHeader(res, const ['Location', 'X-File-URL']);
        final serverHash = map?['sha256']?.toString() ??
            _firstNonEmptyHeader(res, const ['X-Checksum-SHA256', 'ETag']);

        return UploadResult(
          ok: true,
          status: res.statusCode,
          url: url,
          serverHash: serverHash,
        );
      }

      final bodyOrReason = (res.body.isNotEmpty ? res.body : res.reasonPhrase) ?? 'HTTP error';
      return UploadResult(ok: false, status: res.statusCode, error: bodyOrReason);
    } on TimeoutException {
      return const UploadResult(
        ok: false,
        status: 408,
        error: 'Timeout: la subida o la respuesta tardó demasiado',
      );
    } on SocketException catch (e) {
      return UploadResult(ok: false, status: 0, error: 'SocketException: ${e.message}');
    } on HttpException catch (e) {
      return UploadResult(ok: false, status: 0, error: 'HttpException: ${e.message}');
    } catch (e) {
      return UploadResult(ok: false, status: 0, error: 'Error inesperado: $e');
    }
  }

  static String _defaultRequestId() =>
      'req_${DateTime.now().microsecondsSinceEpoch}_${_randSuffix()}';

  static String _idempotencyKeyFor(String sha) => 'upload:$sha';

  static Map<String, dynamic>? _tryJsonMap(String body) {
    try {
      final v = jsonDecode(body);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    return null;
  }

  static String? _firstNonEmptyHeader(http.Response res, List<String> names) {
    for (final n in names) {
      final v = res.headers[n] ?? res.headers[n.toLowerCase()];
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  static String _randSuffix() {
    final ms = DateTime.now().millisecondsSinceEpoch.remainder(100000).toString().padLeft(5, '0');
    return ms;
  }
}

/// Variante local para pruebas offline: simula éxito y devuelve file://
class LocalOkUploader implements PhotoUploader {
  const LocalOkUploader();

  @override
  Future<UploadResult> upload({
    required File file,
    required String sha256hex,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await Future.delayed(const Duration(milliseconds: 120));
    final hash = await computeSha256(file);
    return UploadResult(ok: true, status: 200, url: file.uri.toString(), serverHash: hash);
  }
}

/// Checksum SHA-256 en streaming (sin cargar todo en memoria).
Future<String> computeSha256(File f) async {
  final digest = await sha256.bind(f.openRead()).first;
  return digest.toString();
}
