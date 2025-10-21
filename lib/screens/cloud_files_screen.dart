import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Pantalla de “Planillas en la Nube” SIN backend.
/// Deja el UI listo y muestra un placeholder. Podrás enchufar tu API/Firebase después.
class CloudFilesScreen extends StatefulWidget {
  const CloudFilesScreen({super.key});

  @override
  State<CloudFilesScreen> createState() => _CloudFilesScreenState();
}

class _CloudFilesScreenState extends State<CloudFilesScreen> {
  String _search = '';
  String _filtroFecha = 'Todos';

  // Lista mock para probar UI localmente.
  final List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[
    // {
    //   'nombre': 'Planilla ejemplo',
    //   'fecha': '2025-03-25T10:30:00.000Z',
    //   'latitud': -34.6037,
    //   'longitud': -58.3816,
    //   'mediciones': [
    //     {'progresiva': '1', 'ohm1m': 0.11, 'ohm3m': 0.12, 'observaciones': 'A'},
    //   ],
    // },
  ];

  bool _matchFiltroFecha(String fechaIso) {
    if (_filtroFecha == 'Todos') return true;
    final fecha = DateTime.tryParse(fechaIso) ?? DateTime.now();
    final hoy = DateTime.now();
    if (_filtroFecha == 'Hoy') {
      return fecha.year == hoy.year &&
          fecha.month == hoy.month &&
          fecha.day == hoy.day;
    }
    if (_filtroFecha == 'Semana') {
      final inicioSemana = hoy.subtract(Duration(days: hoy.weekday - 1));
      return fecha.isAfter(inicioSemana.subtract(const Duration(days: 1)));
    }
    if (_filtroFecha == 'Mes') {
      return fecha.year == hoy.year && fecha.month == hoy.month;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _items.where((planilla) {
      final String nombre =
      (planilla['nombre'] ?? '').toString().toLowerCase();
      final String fecha = (planilla['fecha'] ?? '').toString();
      final matchesSearch =
          _search.isEmpty || nombre.contains(_search.toLowerCase());
      final matchesFecha = _matchFiltroFecha(fecha);
      return matchesSearch && matchesFecha;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Planillas en la Nube (sin configurar)'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => setState(() => _filtroFecha = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'Todos', child: Text('Todos')),
              PopupMenuItem(value: 'Hoy', child: Text('Hoy')),
              PopupMenuItem(value: 'Semana', child: Text('Esta semana')),
              PopupMenuItem(value: 'Mes', child: Text('Este mes')),
            ],
            icon: const Icon(Icons.filter_alt),
            tooltip: 'Filtrar por fecha',
          ),
          IconButton(
            tooltip: 'Cómo habilitar la nube',
            icon: const Icon(Icons.help_outline),
            onPressed: () async {
              const url =
                  'https://firebase.google.com/docs/flutter/setup?hl=es-419';
              final uri = Uri.parse(url);
              if (!await canLaunchUrl(uri)) return;
              final ok =
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (!mounted) return;
              if (!ok) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No se pudo abrir la ayuda.')),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Buscador
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar por nombre',
                prefixIcon: const Icon(Icons.search),
                border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onChanged: (v) => setState(() => _search = v.trim()),
            ),
          ),

          if (_items.isEmpty)
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Aún no hay un backend de nube configurado.\n'
                        'Podés agregar Firebase/Firestore o tu propia API más adelante.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final planilla = filtered[index];
                  final String nombre =
                  (planilla['nombre'] ?? 'Sin nombre').toString();
                  final String fecha = (planilla['fecha'] ?? '').toString();
                  final String fechaFormat = fecha.isNotEmpty
                      ? DateFormat('dd/MM/yyyy HH:mm')
                      .format(DateTime.tryParse(fecha) ?? DateTime.now())
                      : '-';
                  final lat = planilla['latitud'];
                  final lon = planilla['longitud'];
                  return Card(
                    margin:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      leading: const Icon(Icons.cloud_off, color: Colors.grey),
                      title: Text(
                        nombre,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Fecha: $fechaFormat'),
                          if (lat != null && lon != null)
                            GestureDetector(
                              onTap: () async {
                                final url =
                                    'https://www.google.com/maps/search/?api=1&query=$lat,$lon';
                                final uri = Uri.parse(url);
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri,
                                      mode: LaunchMode.externalApplication);
                                }
                              },
                              child: const Text(
                                'Abrir ubicación',
                                style: TextStyle(
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          Text(
                            'Mediciones: ${(planilla['mediciones'] as List?)?.length ?? 0}',
                          ),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'ver') {
                            _mostrarDetalles(context, planilla);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'ver', child: Text('Ver detalles')),
                        ],
                      ),
                      onTap: () => _mostrarDetalles(context, planilla),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // ---------- DIALOGO DETALLES EN TABLA -----------------
  void _mostrarDetalles(BuildContext context, Map<String, dynamic> planilla) {
    final mediciones = planilla['mediciones'] as List<dynamic>? ?? const [];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text((planilla['nombre'] ?? 'Sin nombre').toString()),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Fecha: ${(planilla['fecha'] ?? '').toString()}'),
              Text(
                'Ubicación: ${planilla['latitud']} / ${planilla['longitud']}',
              ),
              const SizedBox(height: 8),
              const Text('Mediciones:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              MeasurementTableDialog(mediciones: mediciones),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

// ---------- TABLA DETALLE MEDICIONES ----------
class MeasurementTableDialog extends StatelessWidget {
  const MeasurementTableDialog({super.key, required this.mediciones});
  final List<dynamic> mediciones;

  @override
  Widget build(BuildContext context) {
    if (mediciones.isEmpty) {
      return const Text('Sin mediciones.');
    }
    final headers = (mediciones.first as Map)
        .keys
        .where((k) => k != 'id')
        .map((e) => e.toString())
        .toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: headers
            .map((h) => DataColumn(label: Text(h.toUpperCase())))
            .toList(),
        rows: mediciones
            .map(
              (m) => DataRow(
            cells: headers
                .map((h) => DataCell(Text('${(m as Map)[h] ?? ''}')))
                .toList(),
          ),
        )
            .toList(),
      ),
    );
  }
}
