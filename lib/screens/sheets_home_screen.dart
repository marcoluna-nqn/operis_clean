import 'package:flutter/material.dart';
import '../data/sheet_repo.dart';
import 'beta_sheet_screen.dart';

class SheetsHomeScreen extends StatefulWidget {
  const SheetsHomeScreen({super.key});
  @override
  State<SheetsHomeScreen> createState() => _SheetsHomeScreenState();
}

class _SheetsHomeScreenState extends State<SheetsHomeScreen> {
  List<SheetMeta> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _items = await SheetRepo.all();
    if (mounted) setState(() {});
  }

  Future<void> _newSheetDialog() async {
    final nameCtrl = TextEditingController(text: 'Bitácora');
    final colsCtrl = TextEditingController(text: '5');
    final rowsCtrl = TextEditingController(text: '60');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nueva planilla'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nombre')),
          TextField(
              controller: colsCtrl,
              decoration: const InputDecoration(labelText: 'Columnas'),
              keyboardType: TextInputType.number),
          TextField(
              controller: rowsCtrl,
              decoration: const InputDecoration(labelText: 'Filas'),
              keyboardType: TextInputType.number),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Crear')),
        ],
      ),
    );
    if (ok != true) return;

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final meta = SheetMeta(
      id: id,
      name: nameCtrl.text.trim().isEmpty ? 'Bitácora' : nameCtrl.text.trim(),
      columns: int.tryParse(colsCtrl.text) ?? 5,
      initialRows: int.tryParse(rowsCtrl.text) ?? 60,
    );
    await SheetRepo.upsert(meta);
    if (!mounted) return;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => BetaSheetScreen(
                  sheetId: meta.id,
                  title: meta.name,
                  columns: meta.columns,
                  initialRows: meta.initialRows,
                )));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Planillas')),
      floatingActionButton: FloatingActionButton(
          onPressed: _newSheetDialog, child: const Icon(Icons.post_add)),
      body: _items.isEmpty
          ? const Center(child: Text('Sin planillas. Tocá + para crear.'))
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final m = _items[i];
                return ListTile(
                  title: Text(m.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle:
                      Text('Cols: ${m.columns} · Filas: ${m.initialRows}'),
                  onTap: () async {
                    await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => BetaSheetScreen(
                                  sheetId: m.id,
                                  title: m.name,
                                  columns: m.columns,
                                  initialRows: m.initialRows,
                                )));
                    _load();
                  },
                );
              },
            ),
    );
  }
}
