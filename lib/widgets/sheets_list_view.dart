// lib/widgets/sheets_list_view.dart
import 'package:flutter/material.dart';
import '../models/sheet.dart';

class SheetsListView extends StatelessWidget {
  const SheetsListView({
    super.key,
    required this.items,
    required this.onTap,
    this.onDelete,
  });

  final List<Sheet> items;
  final ValueChanged<Sheet> onTap;
  final ValueChanged<Sheet>? onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final s = items[i];
        final created = DateTime.fromMillisecondsSinceEpoch(s.createdAt);
        return ListTile(
          title: Text(s.name),
          subtitle: Text('Creada: $created  •  ID: ${s.id}'),
          onTap: () => onTap(s),
          trailing: onDelete == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onDelete!(s),
                ),
        );
      },
    );
  }
}
