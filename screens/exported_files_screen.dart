// lib/screens/exported_files_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../services/file_scanner.dart';

class ExportedFilesScreen extends StatefulWidget {
  const ExportedFilesScreen({super.key});

  @override
  State<ExportedFilesScreen> createState() => _ExportedFilesScreenState();
}

class _ExportedFilesScreenState extends State<ExportedFilesScreen> {
  late Future<List<FileInfo>> _future;

  @override
  void initState() {
    super.initState();
    _future = scanReports();
  }

  void _refresh() => setState(() => _future = scanReports());

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yy HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Planillas exportadas'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<FileInfo>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return const Center(child: Text('Error al cargar archivos.'));
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return const Center(
                child:
                    Text('No hay archivos exportados aÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Âºn.'));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final it = items[i];
              final isPdf = it.ext == '.pdf';
              return ListTile(
                leading: Icon(isPdf ? Icons.picture_as_pdf : Icons.grid_on),
                title: Text(it.name, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${fmt.format(it.modified)} ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¢ ${formatSize(it.sizeBytes)} ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¢ ${it.origin}',
                ),
                onTap: () => OpenFilex.open(it.file.path),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    switch (v) {
                      case 'open':
                        await OpenFilex.open(it.file.path);
                        break;
                      case 'share':
                        await Share.shareXFiles([XFile(it.file.path)]);
                        break;
                      case 'delete':
                        final ok = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Eliminar archivo'),
                                content: Text(
                                    'ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚ÂEliminar ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã¢â‚¬Å“${it.name}ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â?'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancelar'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Eliminar'),
                                  ),
                                ],
                              ),
                            ) ??
                            false;
                        if (!ok) return;
                        try {
                          await it.file.delete();
                          if (!mounted) return;
                          _refresh();
                        } catch (_) {
                          if (!context.mounted) {
                            return; // ÃƒÆ’Ã‚Â¢Ãƒâ€¦Ã¢â‚¬Å“ÃƒÂ¢Ã¢â€šÂ¬Ã‚ÂÃƒÆ’Ã‚Â¯Ãƒâ€šÃ‚Â¸Ãƒâ€šÃ‚Â no usar context tras await sin chequear
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('No se pudo eliminar.'),
                            ),
                          );
                        }
                        break;
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'open', child: Text('Abrir')),
                    PopupMenuItem(value: 'share', child: Text('Compartir')),
                    PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
