import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../services/prefs_service.dart';

class ExportCenterScreen extends StatefulWidget {
  const ExportCenterScreen({super.key});
  @override
  State<ExportCenterScreen> createState() => _ExportCenterScreenState();
}

class _ExportCenterScreenState extends State<ExportCenterScreen> {
  String? _lastPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _lastPath = await PrefsService.getLastXlsxPath();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final exists = _lastPath != null && File(_lastPath!).existsSync();
    return CupertinoPageScaffold(
      navigationBar:
          const CupertinoNavigationBar(middle: Text('Exportaciones')),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: exists
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Último XLSX',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Text(_lastPath!,
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        CupertinoButton.filled(
                          onPressed: () => OpenFilex.open(_lastPath!),
                          child: const Text('Abrir'),
                        ),
                        const SizedBox(width: 12),
                        CupertinoButton(
                          onPressed: () => Share.shareXFiles(
                              [XFile(_lastPath!)],
                              subject: 'Bitácora · XLSX'),
                          child: const Text('Compartir'),
                        ),
                      ],
                    ),
                  ],
                )
              : const Center(
                  child: Text('Aún no se registró ninguna exportación.')),
        ),
      ),
    );
  }
}
