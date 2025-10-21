// lib/widgets/smart_sheets_list.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Contrato mínimo que debe cumplir cada item de la lista.
abstract class RecentLike {
  String get id;
  String get title;
  String? get subtitle; // opcional para "Actualizado …"
  bool get starred;
}

/// Lista de planillas con estética iOS y acciones contextuales.
class SmartSheetsList extends StatefulWidget {
  const SmartSheetsList({
    super.key,
    required this.items,
    this.onOpen,
    this.onStar,
    this.onRename,
    this.onDuplicate,
    this.onDelete,
  });

  final List<RecentLike> items;

  /// Handlers (opcionales)
  final void Function(RecentLike s)? onOpen;
  final void Function(RecentLike s)? onStar;
  final void Function(RecentLike s)? onRename;
  final void Function(RecentLike s)? onDuplicate;
  final void Function(RecentLike s)? onDelete;

  @override
  State<SmartSheetsList> createState() => _SmartSheetsListState();
}

class _SmartSheetsListState extends State<SmartSheetsList> {
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (widget.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No hay planillas por ahora.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    return CupertinoScrollbar(
      controller: _scrollCtrl,
      child: ListView.separated(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        itemCount: widget.items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final s = widget.items[i];

          final tile = _SheetTile(
            sheet: s,
            onOpen: widget.onOpen,
            onStar: widget.onStar,
            onRename: widget.onRename,
            onDuplicate: widget.onDuplicate,
            onDelete: widget.onDelete,
          );

          // Si hay onDelete, habilitamos swipe-to-delete
          if (widget.onDelete != null) {
            return Dismissible(
              key: ValueKey('sheet_${s.id}_$i'),
              direction: DismissDirection.endToStart,
              background: _SwipeBg(color: cs.error, icon: Icons.delete_outline),
              onDismissed: (_) => widget.onDelete?.call(s),
              child: tile,
            );
          }
          return tile;
        },
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile({
    required this.sheet,
    this.onOpen,
    this.onStar,
    this.onRename,
    this.onDuplicate,
    this.onDelete,
  });

  final RecentLike sheet;
  final void Function(RecentLike s)? onOpen;
  final void Function(RecentLike s)? onStar;
  final void Function(RecentLike s)? onRename;
  final void Function(RecentLike s)? onDuplicate;
  final void Function(RecentLike s)? onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surface,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: .25),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onOpen?.call(sheet),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: cs.primary.withValues(alpha: .12),
                child: Icon(Icons.description_outlined, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (sheet.title.isEmpty ? 'Sin título' : sheet.title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -.1),
                    ),
                    if (sheet.subtitle != null && sheet.subtitle!.isNotEmpty)
                      Text(
                        sheet.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: sheet.starred ? 'Quitar favorito' : 'Favorito',
                onPressed: () => onStar?.call(sheet),
                icon: Icon(sheet.starred ? Icons.star : Icons.star_border),
              ),
              // Menú contextual (Abrir / Renombrar / Duplicar / Eliminar)
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'open':
                      onOpen?.call(sheet);
                      break;
                    case 'rename':
                      onRename?.call(sheet);
                      break;
                    case 'dup':
                      onDuplicate?.call(sheet);
                      break;
                    case 'delete':
                      onDelete?.call(sheet);
                      break;
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem<String>(
                    value: 'open',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.open_in_new),
                      title: Text('Abrir'),
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'rename',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.drive_file_rename_outline),
                      title: Text('Renombrar'),
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'dup',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.copy_all_outlined),
                      title: Text('Duplicar'),
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.delete_outline),
                      title: Text('Eliminar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeBg extends StatelessWidget {
  const _SwipeBg({required this.color, required this.icon});
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: Colors.white),
    );
  }
}
