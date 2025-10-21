import 'package:flutter/material.dart';
import '../models/measurement.dart';

/// Tabla mínima editable:
/// - Muestra la lista
/// - Permite reordenar y eliminar filas
/// - Llama onChanged con la nueva lista
class EditableMeasurementTable extends StatefulWidget {
  final List<Measurement> measurements;
  final ValueChanged<List<Measurement>> onChanged;
  final bool readOnly;

  const EditableMeasurementTable({
    super.key,
    required this.measurements,
    required this.onChanged,
    this.readOnly = false,
  });

  @override
  State<EditableMeasurementTable> createState() =>
      _EditableMeasurementTableState();
}

class _EditableMeasurementTableState extends State<EditableMeasurementTable> {
  late List<Measurement> _items;

  @override
  void initState() {
    super.initState();
    _items = List<Measurement>.from(widget.measurements);
  }

  void _emit() => widget.onChanged(List<Measurement>.unmodifiable(_items));

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return const Center(child: Text('Sin datos.'));
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: _items.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final item = _items.removeAt(oldIndex);
          _items.insert(newIndex, item);
        });
        _emit();
      },
      itemBuilder: (context, index) {
        final m = _items[index];
        return ListTile(
          key: ValueKey(m.id ?? index),
          leading: const Icon(Icons.drag_handle),
          title: Text(
            m.toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: widget.readOnly
              ? null
              : IconButton(
                  tooltip: 'Eliminar',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    setState(() {
                      _items.removeAt(index);
                    });
                    _emit();
                  },
                ),
        );
      },
    );
  }
}
