import 'package:flutter/material.dart';
import '../services/audit_service.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  List<AuditEvent> _events = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await AuditService.readAll();
    if (!mounted) return;
    setState(() => _events = all.reversed.toList());
  }

  @override
  Widget build(BuildContext context) {
    final events = _events.where((e) {
      if (_query.trim().isEmpty) return true;
      final q = _query.toLowerCase();
      return '${e.action} ${e.field} ${e.key} ${e.newValue} ${e.oldValue}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de cambios'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Vaciar historial',
            onPressed: () async {
              final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Vaciar historial'),
                      content: const Text('Esto eliminará audit.log'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Vaciar'),
                        ),
                      ],
                    ),
                  ) ??
                  false;
              if (!ok) return;
              await AuditService.clear();
              await _load();
            },
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar en historial…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: events.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final e = events[i];
                return ListTile(
                  title: Text('${e.action} • ${e.field} → ${e.newValue}'),
                  subtitle: Text(
                    '${e.ts.toLocal()}  |  key: ${e.key}  |  antes: ${e.oldValue}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  leading: const Icon(Icons.history, size: 20),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
