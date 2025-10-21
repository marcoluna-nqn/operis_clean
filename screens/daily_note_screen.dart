// lib/screens/daily_note_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Bloc de notas simple con dictado.
/// Navega a esta pantalla con:
///   Navigator.push(context, MaterialPageRoute(builder: (_) => const DailyNoteScreen()));
class DailyNoteScreen extends StatefulWidget {
  const DailyNoteScreen({super.key, this.id});
  final String? id;

  @override
  State<DailyNoteScreen> createState() => _DailyNoteScreenState();
}

class _DailyNoteScreenState extends State<DailyNoteScreen> {
  final _titleCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  late final stt.SpeechToText _stt;
  bool _speechAvailable = false;
  bool _listening = false;
  String _localeId = 'es_AR';
  Timer? _levelTimer;
  double _inputLevel = 0.0;

  @override
  void initState() {
    super.initState();
    _stt = stt.SpeechToText();
    _initSpeech();
    _titleCtrl.text = (widget.id == null || widget.id!.isEmpty)
        ? 'Parte diario'
        : 'Parte diario (${widget.id})';
  }

  Future<void> _initSpeech() async {
    try {
      final ok = await _stt.initialize(
        onStatus: _onSpeechStatus,
        onError: (e) => debugPrint('STT error: $e'),
      );
      _speechAvailable = ok;
      final locales = await _stt.locales();
      final es = locales.firstWhere(
            (l) =>
        l.localeId.startsWith('es_') ||
            l.localeId == 'es_ES' ||
            l.localeId == 'es',
        orElse: () => locales.isNotEmpty
            ? locales.first
            : stt.LocaleName('en_US', 'English'),
      );
      _localeId = es.localeId;
    } catch (e) {
      debugPrint('Speech init fail: $e');
      _speechAvailable = false;
    } finally {
      if (mounted) setState(() {});
    }
  }

  void _onSpeechStatus(String status) {
    if (!mounted) return;
    setState(() => _listening = status == 'listening');
  }

  Future<void> _toggleMic() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dictado no disponible en este dispositivo.')),
      );
      return;
    }
    if (_listening) {
      await _stt.stop();
      _stopLevelUpdates();
      setState(() => _listening = false);
      return;
    }

    final ok = await _stt.listen(
      localeId: _localeId,
      // NO usar const: algunas versiones no marcan este ctor como const.
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
      ),
      onResult: (res) {
        if (!mounted) return;
        final txt = res.recognizedWords.trim();
        if (txt.isEmpty) return;
        _insertLiveTranscript(txt, isFinal: res.finalResult);
      },
      onSoundLevelChange: (level) => _inputLevel = level,
    );

    if (ok == true) {
      _startLevelUpdates();
      setState(() => _listening = true);
      await HapticFeedback.selectionClick();
    }
  }

  /// Inserta el dictado al final del cuaderno.
  /// Si es parcial, lo muestra como “texto en vivo” (tag especial) que se reemplaza al final.
  void _insertLiveTranscript(String text, {required bool isFinal}) {
    const liveTag = '［dictado…］';
    final full = _noteCtrl.text;

    // Quita cualquier live previo
    final cleaned = full.replaceAll(RegExp(r'\n?\s*［dictado…］.*$'), '');

    final toAppend = isFinal ? text : '$liveTag $text';
    final next =
    (cleaned.trim().isEmpty ? toAppend : '$cleaned\n$toAppend').trimRight();

    _noteCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );

    if (isFinal) {
      if (!next.endsWith('.') && !next.endsWith('!') && !next.endsWith('?')) {
        _noteCtrl.text = '$next.';
      }
    }
  }

  void _startLevelUpdates() {
    _levelTimer?.cancel();
    _levelTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted) return;
      setState(() {}); // redibuja indicador de nivel
    });
  }

  void _stopLevelUpdates() {
    _levelTimer?.cancel();
    _levelTimer = null;
    setState(() {});
  }

  @override
  void dispose() {
    _levelTimer?.cancel();
    _stt.stop();
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final micEnabled = _speechAvailable;
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bloc de notas'),
        actions: [
          IconButton(
            tooltip: 'Limpiar',
            onPressed: _noteCtrl.text.isEmpty
                ? null
                : () {
              _noteCtrl.clear();
              HapticFeedback.selectionClick();
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          TextField(
            controller: _titleCtrl,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Título',
              prefixIcon: Icon(Icons.title),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            keyboardType: TextInputType.multiline,
            minLines: 12,
            maxLines: 999,
            decoration: const InputDecoration(
              labelText: 'Contenido',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                onPressed: micEnabled ? _toggleMic : null,
                icon: Icon(_listening ? Icons.mic : Icons.mic_none),
                label: Text(_listening ? 'Grabando…' : 'Dictar'),
              ),
              const SizedBox(width: 12),
              if (_listening) _LevelBar(level: _inputLevel, color: accent),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Guardado local (en memoria)')),
                  );
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (!micEnabled)
            const Text(
              'El dictado por voz no está disponible.',
              style: TextStyle(color: Colors.redAccent),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final now = TimeOfDay.now().format(context);
          final next =
          _noteCtrl.text.isEmpty ? '- $now: ' : '${_noteCtrl.text}\n- $now: ';
          _noteCtrl.value = TextEditingValue(
            text: next,
            selection: TextSelection.collapsed(offset: next.length),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Punto'),
      ),
    );
  }
}

class _LevelBar extends StatelessWidget {
  const _LevelBar({required this.level, required this.color});
  final double level; // 0..x (puede ser negativo)
  final Color color;

  @override
  Widget build(BuildContext context) {
    final v = (level + 50) / 60; // aprox
    final clamped = v.clamp(0.0, 1.0);
    return Container(
      width: 120,
      height: 14,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.black12,
      ),
      clipBehavior: Clip.antiAlias,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: clamped,
          child: Container(color: color.withValues(alpha: .6)),
        ),
      ),
    );
  }
}
