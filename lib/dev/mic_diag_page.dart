// lib/dev/mic_diag_page.dart
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class MicDiagPage extends StatefulWidget {
  const MicDiagPage({super.key});
  @override
  State<MicDiagPage> createState() => _MicDiagPageState();
}

class _MicDiagPageState extends State<MicDiagPage> {
  final stt.SpeechToText _stt = stt.SpeechToText();
  String _log = '';
  bool _available = false;

  void _p(String s) => setState(() => _log += '$s\n');

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final ok = await _stt.initialize(
        onStatus: (s) => _p('status: $s'),
        onError: (e) => _p('error: $e'),
      );
      _available = ok;
      _p('initialize: $ok');
      if (!ok) return;

      final sys = await _stt.systemLocale();
      final locs = await _stt.locales();
      _p('systemLocale: ${sys?.localeId}');
      _p('locales: ${locs.map((e) => e.localeId).join(", ")}');

      final stt.LocaleName pick = locs.firstWhere(
            (l) {
          final id = l.localeId;
          return id.startsWith('es_') || id.startsWith('es-') || id == 'es';
        },
        // ⚠️ NO usar const: LocaleName no es const
        orElse: () => stt.LocaleName('en_US', 'English'),
      );
      _p('pick: ${pick.localeId}');

      await _listen(pick.localeId);
    } catch (e) {
      _p('EX: $e');
    }
  }

  Future<void> _listen(String? localeId) async {
    _p('listen(locale=$localeId)');
    final ok = await _stt.listen(
      localeId: localeId,
      // ⚠️ Sin const acá también (seguro con speech_to_text 7.1.0)
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
        onDevice: false,
      ),
      onResult: (res) {
        _p('result: "${res.recognizedWords}" final=${res.finalResult}');
      },
      onSoundLevelChange: (lv) {
        // nivel ignorado en la diag
      },
    );
    _p('listen() returned: $ok');
  }

  Future<void> _stop() async {
    await _stt.stop();
    _p('stopped');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MicDiag')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: _available ? () => _listen(null) : null,
                  child: const Text('Listen (default)'),
                ),
                FilledButton(
                  onPressed: _stop,
                  child: const Text('Stop'),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Text(
                _log,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
