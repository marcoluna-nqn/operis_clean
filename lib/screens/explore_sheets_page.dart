// lib/screens/explore_sheets_page.dart
import 'package:flutter/material.dart';

import '../models/sheet.dart';
import '../widgets/sheets_list_view.dart';
import 'daily_note_screen.dart';

class ExploreSheetsPage extends StatelessWidget {
  const ExploreSheetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: 0,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Planillas'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Planillas'),
              Tab(text: 'Opciones'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _PlanillasTab(),
            _OpcionesTab(),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showCreateMenu(context),
          icon: const Icon(Icons.add),
          label: const Text('Nueva planilla'),
        ),
      ),
    );
  }

  Future<void> _showCreateMenu(BuildContext context) async {
    final nav = Navigator.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.grid_on_outlined),
              title: const Text('Planilla libre (simple)'),
              subtitle: const Text('Títulos y datos editables'),
              onTap: () => Navigator.pop(ctx, 'free'),
            ),
            const Divider(height: 0),
            ListTile(
              leading: const Icon(Icons.notes_outlined),
              title: const Text('Bloc de notas (simple)'),
              subtitle: const Text('Dictado por voz y texto'),
              onTap: () => Navigator.pop(ctx, 'notes'),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;

    if (choice == 'free') {
      if (!nav.mounted) return;
      ScaffoldMessenger.of(nav.context).showSnackBar(
        const SnackBar(
            content: Text('Crear planilla libre (implementá tu flujo).')),
      );
      return;
    }

    if (choice == 'notes') {
      if (!nav.mounted) return;
      nav.push(MaterialPageRoute(builder: (_) => const DailyNoteScreen()));
      return;
    }
  }
}

class _PlanillasTab extends StatefulWidget {
  const _PlanillasTab();

  @override
  State<_PlanillasTab> createState() => _PlanillasTabState();
}

class _PlanillasTabState extends State<_PlanillasTab> {
  DateTime? _filtroFecha;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _filtroFecha ?? now,
                    firstDate: DateTime(now.year - 5, 1, 1),
                    lastDate: DateTime(now.year + 5, 12, 31),
                    helpText: 'Buscar por fecha',
                    cancelText: 'Cancelar',
                    confirmText: 'Buscar',
                  );
                  if (picked != null) setState(() => _filtroFecha = picked);
                },
                icon: const Icon(Icons.calendar_month),
                label: const Text('Calendario'),
              ),
              const SizedBox(width: 8),
              if (_filtroFecha != null)
                TextButton(
                  onPressed: () => setState(() => _filtroFecha = null),
                  child: const Text('Quitar filtro'),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SheetsListView(
            items: const <Sheet>[],
            onTap: (Sheet item) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      'Abrir detalle de planilla ${item.name} (implementá tu flujo).'),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OpcionesTab extends StatelessWidget {
  const _OpcionesTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.restore_from_trash_outlined),
          title: const Text('Recuperar datos borrados'),
          subtitle: const Text('Ver y restaurar planillas eliminadas'),
          onTap: () => Navigator.of(context).pushNamed('/trash'),
        ),
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: const Text('Otras opciones'),
          onTap: () => Navigator.of(context).pushNamed('/settings'),
        ),
      ],
    );
  }
}
