// lib/screens/preview_measurements_screen.dart
import 'package:flutter/material.dart';
import '../models/measurement.dart';
import '../widgets/editable_measurement_table.dart';

class PreviewMeasurementsScreen extends StatefulWidget {
  /// Lista original a previsualizar/editar.
  final List<Measurement> measurements;

  /// Callback opcional para avisar cambios en caliente (p.ej. autosave).
  final ValueChanged<List<Measurement>>? onChanged;

  /// Si es true, no permite guardar ni editar (solo vista previa).
  final bool readOnly;

  const PreviewMeasurementsScreen({
    super.key,
    required this.measurements,
    this.onChanged,
    this.readOnly = false,
  });

  @override
  State<PreviewMeasurementsScreen> createState() =>
      _PreviewMeasurementsScreenState();
}

class _PreviewMeasurementsScreenState extends State<PreviewMeasurementsScreen> {
  late List<Measurement> _editable; // copia local e independiente
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _editable = _clone(widget.measurements);
  }

  List<Measurement> _clone(List<Measurement> src) =>
      src.map((m) => m.copyWith()).toList(growable: true);

  Future<bool> _confirmDiscardIfNeeded() async {
    if (widget.readOnly || !_dirty) return true;
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Descartar cambios'),
            content: const Text(
                'Tenés cambios sin guardar. ¿Querés salir igualmente?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salir'),
              ),
            ],
          ),
        ) ??
        false;
    return ok;
  }

  void _onTableChanged(List<Measurement> updated) {
    // Aseguramos inmutabilidad creando una nueva lista/copia profunda.
    final next = _clone(updated);
    setState(() {
      _editable = next;
      _dirty = true;
    });
    widget.onChanged?.call(List<Measurement>.unmodifiable(next));
  }

  void _saveAndClose() {
    Navigator.pop<List<Measurement>>(
      context,
      List<Measurement>.unmodifiable(_editable),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.readOnly ? 'Vista previa de mediciones' : 'Editar mediciones';

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final ok = await _confirmDiscardIfNeeded();
        if (ok && mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            if (!widget.readOnly)
              TextButton.icon(
                onPressed: _dirty ? _saveAndClose : null,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar'),
              ),
          ],
        ),
        body: _editable.isEmpty
            ? const Center(child: Text('No hay mediciones para mostrar.'))
            : Padding(
                padding: const EdgeInsets.all(8.0),
                child: EditableMeasurementTable(
                  measurements: _editable, // pasamos la copia local
                  onChanged: _onTableChanged,
                  readOnly: widget.readOnly,
                ),
              ),
        floatingActionButton: (!widget.readOnly && _dirty)
            ? FloatingActionButton.extended(
                onPressed: _saveAndClose,
                icon: const Icon(Icons.check),
                label: const Text('Guardar'),
              )
            : null,
      ),
    );
  }
}
