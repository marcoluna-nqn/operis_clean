import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/measurement.dart';
import '../services/autocomplete_service.dart';
import '../services/voice_dictation.dart';
import '../services/location_service.dart';
import '../widgets/ocr_btn.dart';

class EditMeasurementSheet extends StatefulWidget {
  const EditMeasurementSheet({super.key, required this.model});
  final Measurement model;

  @override
  State<EditMeasurementSheet> createState() => _EditMeasurementSheetState();
}

class _EditMeasurementSheetState extends State<EditMeasurementSheet> {
  late final TextEditingController _prog;
  late final TextEditingController _ohm1;
  late final TextEditingController _ohm3;
  late final TextEditingController _obs;
  late final TextEditingController _lat;
  late final TextEditingController _lng;

  String? _errOhm1, _errOhm3, _errLat, _errLng;
  bool _saving = false;
  bool _locating = false;
  List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    final m = widget.model;
    _prog = TextEditingController(text: m.progresiva);
    _ohm1 = TextEditingController(text: '${m.ohm1m ?? ''}');
    _ohm3 = TextEditingController(text: '${m.ohm3m ?? ''}');
    _obs = TextEditingController(text: m.observations);
    _lat = TextEditingController(text: '${m.latitude ?? ''}');
    _lng = TextEditingController(text: '${m.longitude ?? ''}');
    _loadSug();
    _validate();
  }

  @override
  void dispose() {
    _prog.dispose();
    _ohm1.dispose();
    _ohm3.dispose();
    _obs.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  Future<void> _loadSug() async {
    final s = await AutocompleteService.instance.suggestions();
    if (!mounted) return;
    setState(() => _suggestions = s);
  }

  double? _parseNum(String t) {
    final x = t.replaceAll(',', '.').trim();
    if (x.isEmpty) return null;
    return double.tryParse(x);
  }

  bool _validate() {
    _errOhm1 = null;
    _errOhm3 = null;
    _errLat = null;
    _errLng = null;
    if (_ohm1.text.trim().isNotEmpty && _parseNum(_ohm1.text) == null) {
      _errOhm1 = 'Número inválido';
    }
    if (_ohm3.text.trim().isNotEmpty && _parseNum(_ohm3.text) == null) {
      _errOhm3 = 'Número inválido';
    }
    final lat = _parseNum(_lat.text);
    final lng = _parseNum(_lng.text);
    if (_lat.text.trim().isNotEmpty && (lat == null || lat < -90 || lat > 90)) {
      _errLat = 'Lat inválida';
    }
    if (_lng.text.trim().isNotEmpty && (lng == null || lng < -180 || lng > 180)) {
      _errLng = 'Lng inválida';
    }
    setState(() {});
    return _errOhm1 == null &&
        _errOhm3 == null &&
        _errLat == null &&
        _errLng == null;
  }

  Future<void> _useCurrentLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final pos = await LocationService.instance.getCurrent();
      if (!mounted) return;
      setState(() {
        _lat.text = pos.latitude.toStringAsFixed(6);
        _lng.text = pos.longitude.toStringAsFixed(6);
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ubicación capturada')),
      );
    } on LocationException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('GPS: ${e.message}')),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (!_validate()) return;
    setState(() => _saving = true);
    final m = widget.model.copyWith(
      progresiva: _prog.text.trim(),
      ohm1m: _parseNum(_ohm1.text),
      ohm3m: _parseNum(_ohm3.text),
      observations: _obs.text.trim(),
      latitude: _parseNum(_lat.text),
      longitude: _parseNum(_lng.text),
    );
    if (!mounted) return;
    Navigator.pop(context, m);
  }

  Future<void> _dictate() async {
    final text = await VoiceDictation.instance.listenOnce();
    if (text == null || !mounted) return;
    setState(() => _obs.text = _obs.text.isEmpty ? text : '${_obs.text} $text');
  }

  // --- OCR adaptado a OcrBtn(onText: ...) ---
  void _handleOcrText(String raw) {
    // Busca los 2 primeros números en el texto (con . o ,)
    final re = RegExp(r'(\d+(?:[.,]\d+)?)');
    final matches = re.allMatches(raw).toList();
    double? n1, n3;
    if (matches.isNotEmpty) {
      n1 = _parseNum(matches[0].group(1)!);
      if (matches.length > 1) n3 = _parseNum(matches[1].group(1)!);
    }
    if (n1 != null) _ohm1.text = n1.toStringAsFixed(2);
    if (n3 != null) _ohm3.text = n3.toStringAsFixed(2);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Valores cargados desde OCR')),
    );
    _validate();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final canSave = _errOhm1 == null &&
        _errOhm3 == null &&
        _errLat == null &&
        _errLng == null;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 4,
                width: 40,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(4)),
              ),
              Row(
                children: [
                  const Expanded(
                      child: Text('Editar medición',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close)),
                ],
              ),
              TextField(
                  controller: _prog,
                  decoration: const InputDecoration(labelText: 'Progresiva'),
                  textInputAction: TextInputAction.next),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ohm1,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: '1m (Ω)', errorText: _errOhm1),
                      onChanged: (_) => _validate(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _ohm3,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: '3m (Ω)', errorText: _errOhm3),
                      onChanged: (_) => _validate(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // ⬇️ ahora cumple con el constructor actual de OcrBtn
                  OcrBtn(onText: _handleOcrText),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _lat,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]'))
                      ],
                      decoration: InputDecoration(
                          labelText: 'Latitud', errorText: _errLat),
                      onChanged: (_) => _validate(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _lng,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]'))
                      ],
                      decoration: InputDecoration(
                          labelText: 'Longitud', errorText: _errLng),
                      onChanged: (_) => _validate(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Usar ubicación actual',
                    onPressed: _locating ? null : _useCurrentLocation,
                    icon: _locating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              RawAutocomplete<String>(
                optionsBuilder: (t) async {
                  final q = t.text.trim();
                  return AutocompleteService.instance.suggestions(q: q);
                },
                displayStringForOption: (o) => o,
                onSelected: (v) => _obs.text = v,
                fieldViewBuilder: (ctx, ctrl, focus, onSubmit) {
                  ctrl.text = _obs.text;
                  ctrl.selection =
                      TextSelection.collapsed(offset: ctrl.text.length);
                  return TextField(
                    controller: ctrl,
                    focusNode: focus,
                    maxLines: null,
                    decoration: InputDecoration(
                      labelText: 'Observaciones',
                      suffixIcon: IconButton(
                          onPressed: _dictate,
                          icon: const Icon(Icons.mic),
                          tooltip: 'Dictar'),
                    ),
                    onChanged: (v) => _obs.text = v,
                  );
                },
                optionsViewBuilder: (ctx, onSelected, options) {
                  final opts = options.toList();
                  if (opts.isEmpty) return const SizedBox.shrink();
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxHeight: 200, maxWidth: 600),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: opts.length,
                          itemBuilder: (_, i) => ListTile(
                            title: Text(opts[i]),
                            onTap: () => onSelected(opts[i]),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: -8,
                    children: _suggestions
                        .take(6)
                        .map((s) => ActionChip(
                              label: Text(s),
                              onPressed: () => setState(() => _obs.text = s),
                            ))
                        .toList(),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (!_saving && canSave) ? _save : null,
                  child: _saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Guardar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
