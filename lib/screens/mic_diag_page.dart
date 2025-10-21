import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class MicDiagPage extends StatefulWidget {
  const MicDiagPage({super.key});
  @override
  State<MicDiagPage> createState() => _MicDiagPageState();
}

class _MicDiagPageState extends State<MicDiagPage> {
  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _available = false;
  bool _listening = false;
  String _status = 'idle';
  String _text = '';
  String? _error;
  String? _localeId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ok = await _stt.initialize(
      onStatus: (s) {
        if (!mounted) return;
        setState(() => _status = s);
        debugPrint('STT status: $s');
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _error = '${e.errorMsg} perm=${e.permanent}');
        debugPrint('STT error: ${e.errorMsg} permanent=${e.permanent}');
      },
      debugLogging: false,
    );
    String? loc;
    try {
      final sys = await _stt.systemLocale();
      loc = sys?.localeId;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _available = ok;
      _localeId = loc; // ej: es_AR
    });
  }

  Future<void> _toggle() async {
    if (_stt.isListening) {
      await _stt.stop();
      if (!mounted) return;
      setState(() => _listening = false);
      return;
    }
    if (!_available) {
      await _init();
      if (!_available) return;
    }
    await _stt.listen(
      localeId: _localeId ?? 'es_AR',
      listenFor: const Duration(seconds: 12),
      pauseFor: const Duration(milliseconds: 1500),
      partialResults: true,
      cancelOnError: true,
      onResult: (res) {
        if (!mounted) return;
        setState(() => _text = res.recognizedWords);
        debugPrint('> ${res.recognizedWords} final=${res.finalResult}');
      },
    );
    if (!mounted) return;
    setState(() => _listening = true);
  }

  @override
  void dispose() {
    _stt.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final infoStyle = Theme.of(context).textTheme.bodyMedium;
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnóstico de mic')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Disponible: ${_available ? 'sí' : 'no'}', style: infoStyle),
          Text('Locale: ${_localeId ?? '-'}', style: infoStyle),
          Text('Estado: $_status', style: infoStyle),
          if (_error != null)
            Text('Error: $_error', style: infoStyle?.copyWith(color: Colors.red)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_text.isEmpty ? '—' : _text),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _toggle,
              icon: Icon(_listening ? Icons.stop_circle : Icons.mic),
              label: Text(_listening ? 'Detener' : 'Hablar'),
            ),
          ),
        ]),
      ),
    );
  }
}
