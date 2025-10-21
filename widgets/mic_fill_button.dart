// lib/widgets/mic_fill_button.dart
import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/speech_service.dart';

class MicFillButton extends StatefulWidget {
  const MicFillButton({super.key, required this.controller, this.locale});
  final TextEditingController controller;
  final String? locale;

  @override
  State<MicFillButton> createState() => _MicFillButtonState();
}

class _MicFillButtonState extends State<MicFillButton> {
  bool _disabled = true;
  bool _listening = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initStt();
  }

  Future<void> _initStt() async {
    final ok = await SpeechService.I.init(preferredLocale: widget.locale ?? 'es_AR');
    if (!mounted) return;
    setState(() => _disabled = !ok);
  }

  @override
  void dispose() {
    SpeechService.I.cancel();
    super.dispose();
  }

  Future<void> _ensureMicPermission() async {
    final st = await Permission.microphone.status;
    if (st.isGranted) return;
    final req = await Permission.microphone.request();
    if (!req.isGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Habilitá el micrófono en Ajustes')),
      );
      await openAppSettings();
    }
  }

  Future<void> _start() async {
    if (_busy || _disabled || _listening) return;
    _busy = true;
    await _ensureMicPermission();
    if (!mounted) { _busy = false; return; }

    setState(() => _listening = true);
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();

    // Escucha una vez y completa el controller. Sin params no soportados.
    await SpeechService.I.fillControllerOnce(
      widget.controller,
      localeId: widget.locale,
    );

    if (!mounted) { _busy = false; return; }
    setState(() => _listening = false);
    HapticFeedback.selectionClick();
    _busy = false;
  }

  Future<void> _stop() async {
    if (_busy) return;
    await SpeechService.I.stop();
    if (!mounted) return;
    setState(() => _listening = false);
    HapticFeedback.lightImpact();
  }

  Future<void> _toggle() async {
    if (_disabled) {
      await _ensureMicPermission();
      return;
    }
    if (_listening) {
      await _stop();
    } else {
      unawaited(_start());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = _listening ? 1.06 : 1.0;
    final bgAlpha = _listening ? 0.25 : 0.08;

    return GestureDetector(
      onLongPressStart: (_) => unawaited(_start()), // push-to-talk
      onLongPressEnd:   (_) => unawaited(_stop()),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: bgAlpha),
          shape: BoxShape.circle,
        ),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 120),
          child: IconButton.filledTonal(
            onPressed: () { unawaited(_toggle()); },
            icon: Icon(_listening ? Icons.mic : Icons.mic_none),
            tooltip: _disabled
                ? 'Micrófono no disponible'
                : (_listening ? 'Detener dictado' : 'Dictar'),
          ),
        ),
      ),
    );
  }
}
