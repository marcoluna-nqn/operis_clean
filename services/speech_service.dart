// lib/services/speech_service.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  SpeechService._();
  static final SpeechService I = SpeechService._();

  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _inited = false;
  bool _available = false;
  bool _listening = false;
  String? _localeId;

  bool get isAvailable => _available;
  bool get isListening => _listening;
  String? get currentLocale => _localeId;

  /// Inicializa STT y elige un locale (sistema → español → preferred → en_US).
  Future<bool> init({String? preferredLocale}) async {
    if (_inited) return _available;

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      _inited = true;
      _available = false;
      return false;
    }

    try {
      _available = await _stt.initialize(
        onError: (e) => debugPrint('STT error: $e'),
        onStatus: (s) => debugPrint('STT status: $s'),
      );

      if (_available) {
        final sys = await _stt.systemLocale();
        final locales = await _stt.locales();

        String? pick;
        // 1) locale de sistema
        if (sys?.localeId != null && sys!.localeId.isNotEmpty) {
          pick = sys.localeId;
        }
        // 2) español cualquiera
        pick ??= locales
            .where((l) => l.localeId.toLowerCase().startsWith('es'))
            .map((l) => l.localeId)
            .cast<String?>()
            .firstOrNull;
        // 3) preferido exacto si está
        if (preferredLocale != null) {
          final variants = {
            preferredLocale,
            preferredLocale.replaceAll('_', '-'),
            preferredLocale.replaceAll('-', '_'),
          };
          final hit = locales.firstWhere(
                (l) => variants.contains(l.localeId),
            orElse: () => stt.LocaleName('', ''), // ← sin const
          );
          if (hit.localeId.isNotEmpty) pick ??= hit.localeId;
        }
        // 4) fallback final
        pick ??= 'en_US';

        _localeId = pick;
        debugPrint('STT locale: $_localeId');
      }
    } catch (e) {
      debugPrint('STT init failed: $e');
      _available = false;
    } finally {
      _inited = true;
    }
    return _available;
  }

  /// Escucha una sola vez. Devuelve el texto final (o parcial si hay timeout).
  Future<String?> listenOnce({
    String? localeId,
    ValueChanged<String>? partial,
    ValueChanged<double>? level, // nivel 0..1 para UI
    Duration autoTimeout = const Duration(seconds: 60),
  }) async {
    if (!await init()) return null;

    if (_listening) {
      await stop();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    Future<String?> run(String? loc) async {
      final completer = Completer<String?>();
      String lastPartial = '';
      _listening = true;

      try {
        final ok = await _stt.listen(
          localeId: loc,
          listenOptions: stt.SpeechListenOptions(
            listenMode: stt.ListenMode.dictation,
            partialResults: true,
            cancelOnError: true,
            onDevice: false,
          ),
          onResult: (res) {
            final txt = res.recognizedWords.trim();
            if (txt.isNotEmpty) {
              lastPartial = txt;
              partial?.call(txt);
            }
            if (res.finalResult && !completer.isCompleted) {
              completer.complete(txt);
            }
          },
          onSoundLevelChange: (raw) {
            final v = ((raw + 2.0) / 10.0).clamp(0.0, 1.0);
            level?.call(v);
          },
        );

        if ((ok == false) && !completer.isCompleted) {
          completer.complete(null);
        }

        // Timeout externo
        Future.delayed(autoTimeout, () {
          if (!completer.isCompleted) {
            completer.complete(lastPartial.isEmpty ? null : lastPartial);
          }
          stop();
        });
      } on PlatformException catch (e) {
        debugPrint('STT listen error: $e');
        if (!completer.isCompleted) completer.complete(null);
      }

      final result = await completer.future;
      await stop();
      return result;
    }

    // 1) con locale elegido
    final first = await run(localeId ?? _localeId);
    if (first != null && first.isNotEmpty) return first;

    // 2) sin locale (deja que el servicio decida)
    if ((localeId ?? _localeId) != null) {
      debugPrint('STT retry with null locale');
      final second = await run(null);
      if (second != null && second.isNotEmpty) return second;
    }

    // 3) último recurso: en_US
    return await run('en_US');
  }

  /// Rellena un TextEditingController con dictado en vivo (parciales) y final.
  Future<void> fillControllerOnce(
      TextEditingController controller, {
        String? localeId,
        Duration autoTimeout = const Duration(seconds: 60),
      }) async {
    await listenOnce(
      localeId: localeId,
      autoTimeout: autoTimeout,
      partial: (txt) {
        controller.text = txt;
        controller.selection = TextSelection.collapsed(offset: txt.length);
      },
    );
  }

  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {} finally {
      _listening = false;
    }
  }

  Future<void> cancel() async {
    try {
      await _stt.cancel();
    } catch (_) {} finally {
      _listening = false;
    }
  }
}

extension<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
