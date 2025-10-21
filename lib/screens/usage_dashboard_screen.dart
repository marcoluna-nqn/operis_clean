// lib/screens/usage_dashboard_screen.dart
import 'package:flutter/material.dart';

/// Pantalla de uso sin dependencias externas.
/// - Elimina UsageAnalytics y GridnoteTheme.
/// - Permite inyectar un loader opcional que devuelva Map<String,int>.
class UsageDashboardScreen extends StatefulWidget {
  const UsageDashboardScreen({
    super.key,
    this.title = 'Uso (beta)',
    this.loader,
  });

  /// Título de la pantalla.
  final String title;

  /// Función que devuelve los contadores de uso.
  /// Si es null, se muestra un mapa vacío.
  final Future<Map<String, int>> Function()? loader;

  @override
  State<UsageDashboardScreen> createState() => _UsageDashboardScreenState();
}

class _UsageDashboardScreenState extends State<UsageDashboardScreen> {
  Map<String, int> _data = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final m = await (widget.loader?.call() ?? Future.value(<String, int>{}));
      if (!mounted) return;
      setState(() {
        _data = m;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _data = const {};
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).colorScheme.outlineVariant;
    final total = _data.values.fold<int>(0, (a, b) => a + b);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data.isEmpty
              ? const Center(child: Text('Sin datos aún'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _data.length,
                  separatorBuilder: (_, __) => Divider(color: divider),
                  itemBuilder: (_, i) {
                    final key = _data.keys.elementAt(i);
                    final count = _data[key] ?? 0;
                    final pct = total == 0 ? 0.0 : (count * 100.0 / total);
                    return ListTile(
                      title: Text(key),
                      subtitle: Text(
                        '${pct.toStringAsFixed(1)}% • $count eventos',
                      ),
                    );
                  },
                ),
    );
  }
}
