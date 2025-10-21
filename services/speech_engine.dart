// lib/services/speech_engine.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Resultado normalizado hacia la app.
class SpeechResult {
  final String recognizedWords;
  final bool finalResult;
  const SpeechResult({
    required this.recognizedWords,
    required this.finalResult,
  });
}

/// Modo de escucha abstracto (propio de la app).
enum ListenMode { dictation, confirmation, search }

stt.ListenMode _mapMode(ListenMode m) {
  switch (m) {
    case ListenMode.confirmation:
      return stt.ListenMode.confirmation;
    case ListenMode.search:
      return stt.ListenMode.search;
    case ListenMode.dictation:
    default:
      return stt.ListenMode.dictation;
  }
}

/// Opciones de escucha usadas por la app.
/// (Si tu versión del plugin no soporta ciertos campos,
/// igualmente los mantenemos para control en la capa superior.)
class SpeechListenOptions {
  final ListenMode listenMode;
  final bool partialResults;
  final bool cancelOnError;
  final bool onDevice;

  /// Tiempo máximo deseado para la sesión (lo maneja la capa superior).
  final Duration? listenFor;

  /// Silencio para corte (lo maneja la capa superior).
  final Duration? pauseFor;

  const SpeechListenOptions({
    this.listenMode = ListenMode.dictation,
    this.partialResults = true,
    this.cancelOnError = false,
    this.onDevice = false,
    this.listenFor = const Duration(seconds: 15),
    this.pauseFor = const Duration(seconds: 2),
  });

  SpeechListenOptions copyWith({
    ListenMode? listenMode,
    bool? partialResults,
    bool? cancelOnError,
    bool? onDevice,
    Duration? listenFor,
    Duration? pauseFor,
  }) {
    return SpeechListenOptions(
      listenMode: listenMode ?? this.listenMode,
      partialResults: partialResults ?? this.partialResults,
      cancelOnError: cancelOnError ?? this.cancelOnError,
      onDevice: onDevice ?? this.onDevice,
      listenFor: listenFor ?? this.listenFor,
      pauseFor: pauseFor ?? this.pauseFor,
    );
  }
}

/// Interfaz del motor STT.
abstract class SpeechEngine {
  Future<bool> initialize({
    required void Function(Object error, StackTrace? st) onError,
    required void Function(String status) onStatus,
  });

  Future<List<String>> locales();
  Future<String?> systemLocale();

  Future<bool> listen({
    String? localeId,
    required SpeechListenOptions listenOptions,
    required ValueChanged<SpeechResult> onResult,
    required ValueChanged<double> onSoundLevelChange,
  });

  Future<void> stop();
  Future<void> cancel();
}

/// Adaptador a `speech_to_text`.
class SpeechToTextEngine implements SpeechEngine {
  final stt.SpeechToText _stt = stt.SpeechToText();

  @override
  Future<bool> initialize({
    required void Function(Object error, StackTrace? st) onError,
    required void Function(String status) onStatus,
  }) async {
    try {
      final ok = await _stt.initialize(
        onStatus: (s) => onStatus(s),
        onError: (e) => onError(e, null), // compatible con distintas versiones
      );
      return ok == true;
    } catch (e, st) {
      onError(e, st);
      return false;
    }
  }

  @override
  Future<List<String>> locales() async {
    try {
      final list = await _stt.locales();
      return list.map((e) => e.localeId).toList();
    } catch (_) {
      return const <String>[];
    }
  }

  @override
  Future<String?> systemLocale() async {
    try {
      final v = await _stt.systemLocale();
      return v?.localeId;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> listen({
    String? localeId,
    required SpeechListenOptions listenOptions,
    required ValueChanged<SpeechResult> onResult,
    required ValueChanged<double> onSoundLevelChange,
  }) async {
    try {
      // En tu versión del plugin, `listenFor`/`pauseFor` NO existen ni aquí
      // ni dentro de SpeechListenOptions del plugin. Los maneja la capa superior.
      final pluginOpts = stt.SpeechListenOptions(
        listenMode: _mapMode(listenOptions.listenMode),
        partialResults: listenOptions.partialResults,
        cancelOnError: listenOptions.cancelOnError,
        onDevice: listenOptions.onDevice,
      );

      final ok = await _stt.listen(
        localeId: localeId,
        listenOptions: pluginOpts,
        onResult: (dynamic r) {
          // Acceso dinámico para ser compatible con varias versiones del plugin
          try {
            final words = (r as dynamic).recognizedWords?.toString() ?? '';
            final isFinal = (r as dynamic).finalResult == true;
            onResult(SpeechResult(recognizedWords: words, finalResult: isFinal));
          } catch (_) {
            onResult(const SpeechResult(recognizedWords: '', finalResult: false));
          }
        },
        onSoundLevelChange: (lv) => onSoundLevelChange(_asDouble(lv)),
      );

      return ok == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }

  @override
  Future<void> cancel() async {
    try {
      await _stt.cancel();
    } catch (_) {}
  }

  double _asDouble(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }
}
