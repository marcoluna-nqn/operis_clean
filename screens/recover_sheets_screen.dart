// lib/screens/recover_sheets_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RecoverSheetsScreen extends ConsumerWidget {
  const RecoverSheetsScreen({
    super.key,
    this.loader,
    this.onRestore,
  });

  final Future<List<TrashItem>> Function()? loader;
  final Future<void> Function(TrashItem item)? onRestore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar planillas')),
      body: FutureBuilder<List<TrashItem>>(
        future: loader != null ? loader!() : Future.value(const <TrashItem>[]),
        builder: (context, snap) {
          final waiting = snap.connectionState == ConnectionState.waiting;
          final items = snap.data ?? const <TrashItem>[];

          if (waiting) return const _SkeletonList();

          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No hay planillas en papelera.\n\n'
                  'Cuando el borrado sea “suave”, las planillas se mostrarán aquí '
                  'por un tiempo antes de eliminarse definitivamente.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onSurface.withOpacity(.7),
                    height: 1.4,
                  ),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemBuilder: (_, i) {
              final it = items[i];
              return ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: const Icon(Icons.description_outlined),
                title: Text(
                  it.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'Eliminada hace ${_ago(it.deletedAt)}',
                  style: TextStyle(color: scheme.onSurface.withOpacity(.7)),
                ),
                trailing: FilledButton(
                  onPressed: () async {
                    if (onRestore != null) {
                      await onRestore!(it);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Planilla restaurada')),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Restaurado (demo)')),
                      );
                    }
                  },
                  child: const Text('Restaurar'),
                ),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemCount: items.length,
          );
        },
      ),
    );
  }

  static String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours} h';
    return '${diff.inDays} d';
  }
}

class TrashItem {
  final String id;
  final String title;
  final DateTime deletedAt;
  const TrashItem({
    required this.id,
    required this.title,
    required this.deletedAt,
  });
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();
  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemBuilder: (_, __) => Container(
        height: 64,
        decoration: BoxDecoration(
          color: surface.withOpacity(.08),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemCount: 8,
    );
  }
}
