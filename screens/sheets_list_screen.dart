// lib/screens/sheets_list_screen.dart
import 'package:flutter/material.dart';
// ¡OJO! no importes local_db.dart aquí para evitar choque de tipos.
import '../models/sheet.dart' as model;
import '../repositories/sheets_repo.dart';
import 'sheet_detail_screen.dart';

class SheetsListScreen extends StatefulWidget {
  const SheetsListScreen({super.key, required this.repo});
  final SheetsRepo repo;

  @override
  State<SheetsListScreen> createState() => _SheetsListScreenState();
}

class _SheetsListScreenState extends State<SheetsListScreen> {
  late Future<List<model.Sheet>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repo.listSheets(); // devuelve List<model.Sheet>
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.repo.listSheets();
    });
  }

  Future<void> _create() async {
    final name = 'Planilla ${DateTime.now().millisecondsSinceEpoch}';
    final id = await widget.repo.newSheet(name);
    await _reload();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SheetDetailScreen(repo: widget.repo, sheetId: id),
      ),
    );
    await _reload();
  }

  Future<void> _rename(model.Sheet s) async {
    final controller = TextEditingController(text: s.name);
    final ok = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Renombrar planilla'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != null && ok.isNotEmpty) {
      await widget.repo.renameSheet(s.id, ok);
      await _reload();
    }
  }

  Future<void> _delete(model.Sheet s) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar planilla'),
        content:
            Text('¿Eliminar "${s.name}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (sure == true) {
      await widget.repo.deleteSheet(s.id);
      await _reload();
    }
  }

  DateTime _asDateTime(dynamic v) {
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Planillas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        label: const Text('Nueva'),
        icon: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<model.Sheet>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data ?? const <model.Sheet>[];
          if (data.isEmpty) {
            return const Center(child: Text('Sin planillas. Crea la primera.'));
          }
          return ListView.builder(
            itemCount: data.length,
            itemBuilder: (_, i) {
              final s = data[i];
              final created = _asDateTime(s.createdAt);
              final dd =
                  '${created.day.toString().padLeft(2, '0')}/${created.month.toString().padLeft(2, '0')}/${created.year}';
              return ListTile(
                leading: const Icon(Icons.description_outlined),
                title:
                    Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('Creada: $dd • ID ${s.id}'),
                trailing: Wrap(spacing: 4, children: [
                  IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _rename(s)),
                  IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(s)),
                ]),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          SheetDetailScreen(repo: widget.repo, sheetId: s.id),
                    ),
                  );
                  await _reload();
                },
              );
            },
          );
        },
      ),
    );
  }
}
