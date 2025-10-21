// lib/screens/browse_sheets_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/sheet.dart'; // ✅ usamos este Sheet (modelo simple)
import '../repositories/sheets_repo.dart';
import 'sheet_detail_screen.dart';

class BrowseSheetsScreen extends StatefulWidget {
  const BrowseSheetsScreen({super.key, required this.repo});
  final SheetsRepo repo;

  @override
  State<BrowseSheetsScreen> createState() => _BrowseSheetsScreenState();
}

class _BrowseSheetsScreenState extends State<BrowseSheetsScreen> {
  late Future<List<Sheet>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repo.listSheets();
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.repo.listSheets();
    });
  }

  Future<void> _createSheet() async {
    final name = 'Planilla ${DateTime.now().millisecondsSinceEpoch}';
    final newId = await widget.repo.newSheet(name);
    await _reload();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SheetDetailScreen(repo: widget.repo, sheetId: newId),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planillas'),
        actions: [
          IconButton(
            tooltip: 'Nueva',
            onPressed: _createSheet,
            icon: const Icon(CupertinoIcons.add),
          ),
        ],
      ),
      body: FutureBuilder<List<Sheet>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final sheets = snap.data ?? const <Sheet>[];
          if (sheets.isEmpty) {
            return const Center(child: Text('No hay planillas aún.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: sheets.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final s = sheets[i];

              final created = DateTime.fromMillisecondsSinceEpoch(s.createdAt);
              final dd =
                  '${created.day.toString().padLeft(2, '0')}/${created.month.toString().padLeft(2, '0')}/${created.year}';

              return ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: const Icon(CupertinoIcons.doc_text),
                title:
                    Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  'Creada: $dd • ID: ${s.id}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          SheetDetailScreen(repo: widget.repo, sheetId: s.id),
                    ),
                  );
                  await _reload();
                },
                trailing: IconButton(
                  tooltip: 'Eliminar',
                  icon: const Icon(CupertinoIcons.delete_simple),
                  onPressed: () async {
                    await widget.repo.deleteSheet(s.id);
                    await _reload();
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createSheet,
        icon: const Icon(Icons.add),
        label: const Text('Nueva'),
      ),
    );
  }
}
