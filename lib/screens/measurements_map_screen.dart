// lib/screens/measurements_map_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/measurement.dart';

class MeasurementsMapScreen extends StatefulWidget {
  final List<Measurement> measurements;
  const MeasurementsMapScreen({super.key, required this.measurements});

  @override
  State<MeasurementsMapScreen> createState() => _MeasurementsMapScreenState();
}

class _MeasurementsMapScreenState extends State<MeasurementsMapScreen> {
  late final List<Measurement> _points;
  late final List<Marker> _markers;
  late final LatLngBounds _bounds;
  final _mapController = MapController();

  @override
  void initState() {
    super.initState();

    _points = widget.measurements
        .where((m) => m.latitude != null && m.longitude != null)
        .toList();

    _markers = _points
        .map(
          (m) => Marker(
            point: LatLng(m.latitude!, m.longitude!),
            width: 40,
            height: 40,
            child: Tooltip(
              message: '${m.progresiva}\n${m.observations}',
              child: const Icon(Icons.location_on, size: 36, color: Colors.red),
            ),
          ),
        )
        .toList();

    _bounds = _points.isEmpty
        ? LatLngBounds.fromPoints([
            // Fallback (NeuquÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©n) ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â no se usarÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¡ si no hay puntos, ver build()
            const LatLng(-38.9516, -68.0591),
            const LatLng(-38.9516, -68.0591),
          ])
        : LatLngBounds.fromPoints(
            _points.map((m) => LatLng(m.latitude!, m.longitude!)).toList(),
          );
  }

  @override
  Widget build(BuildContext context) {
    if (_points.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mapa de Mediciones')),
        body: const Center(
          child: Text(
            'No hay mediciones con coordenadas para mostrar.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa de Mediciones'),
        actions: [
          IconButton(
            tooltip: 'Ajustar vista',
            icon: const Icon(Icons.center_focus_strong),
            onPressed: () {
              _mapController.fitCamera(
                CameraFit.bounds(
                  bounds: _bounds,
                  padding: const EdgeInsets.all(50),
                ),
              );
            },
          ),
        ],
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCameraFit: CameraFit.bounds(
            bounds: _bounds,
            padding: const EdgeInsets.all(50),
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.gridnote',
          ),
          MarkerLayer(markers: _markers),
        ],
      ),
    );
  }
}
