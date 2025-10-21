import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/sheet_registry.dart';

DateTime _toDt(dynamic v) {
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
  return DateTime.now();
}

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key});

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  static const List<int> _daysOptions = [7, 14, 30];
  int _days = 14;
  bool _loading = true;
  List<_TrashItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final reg = SheetRegistry.instance as dynamic;

      final rawDyn = await (reg.recentlyDeleted?.call(days: _days) ??
          reg.getDeletedSince?.call(Duration(days: _days)) ??
          Future.value(<dynamic>[]));

      final List<dynamic> raw = (rawDyn as List?) ?? const [];

      final items = <_TrashItem>[];
      for (final r in raw) {
        final String id = (r is Map ? r['id'] : r.id)?.toString() ?? '';
        final String title =
            (r is Map ? r['name'] : r.name)?.toString() ?? 'Planilla';
        final DateTime deletedAt = _toDt(r is Map ? r['deletedAt'] : r.deletedAt);
        items.add(_TrashItem(id: id, title: title, deletedAt: deletedAt));
      }
      if (!mounted) return;
      setState(() {
        _items = items..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La recuperación no está disponible en esta build.'),
        ),
      );
    }
  }

  Future<void> _restore(_TrashItem it) async {
    try {
      final reg = SheetRegistry.instance as dynamic;
      await (reg.restore?.call(it.id) ??
          reg.restoreById?.call(it.id) ??
          Future.value());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restaurada: ${it.title}')),
      );
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo restaurar esta planilla')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).colorScheme.outlineVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar planillas borradas')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Text('Mostrar de los últimos:'),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: _days,
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _days = v);
                    _load();
                  },
                  items: _daysOptions
                      .map((d) => DropdownMenuItem(
                    value: d,
                    child: Text('$d días'),
                  ))
                      .toList(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No hay planillas para recuperar en este período.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
                : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: _items.length,
              separatorBuilder: (_, __) => Divider(color: divider),
              itemBuilder: (_, i) {
                final it = _items[i];
                final when =
                    '${it.deletedAt.day.toString().padLeft(2, '0')}/${it.deletedAt.month.toString().padLeft(2, '0')} '
                    '${it.deletedAt.hour.toString().padLeft(2, '0')}:${it.deletedAt.minute.toString().padLeft(2, '0')}';
                return ListTile(
                  leading: const Icon(CupertinoIcons.doc_fill),
                  title: Text(
                    it.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('Eliminada: $when'),
                  trailing: FilledButton(
                    onPressed: () => _restore(it),
                    child: const Text('Restaurar'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TrashItem {
  final String id;
  final String title;
  final DateTime deletedAt;
  const _TrashItem({
    required this.id,
    required this.title,
    required this.deletedAt,
  });
}
