// lib/services/ubicacion.dart
import 'package:geolocator/geolocator.dart';

Future<Position> obtenerPosicion() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    await Geolocator.openLocationSettings();
    throw Exception('GPS desactivado');
  }
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
  }
  if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
    await Geolocator.openAppSettings();
    throw Exception('Permiso de ubicación denegado');
  }
  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 10),
    ),
  );
}
