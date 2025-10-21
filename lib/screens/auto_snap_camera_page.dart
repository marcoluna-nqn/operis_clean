// lib/screens/auto_snap_camera_page.dart
import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/photo_store.dart';
import '../services/crash_guard.dart';
import '../shared/sheet_limits.dart'; // kMaxPhotosTotal

const int kSnapCountdownSec = 3;

class AutoSnapCameraPage extends StatefulWidget {
  const AutoSnapCameraPage({
    super.key,
    required this.sheetId,
    required this.rowId,
  });

  final String sheetId;
  final Object rowId;

  @override
  State<AutoSnapCameraPage> createState() => _AutoSnapCameraPageState();
}

class _AutoSnapCameraPageState extends State<AutoSnapCameraPage> {
  CameraController? _controller;
  String? _error;
  bool _taking = false;
  bool _popped = false;

  int _remaining = 0;
  Timer? _ticker;

  bool _permDeniedForever = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) {
        setState(() {
          _permDeniedForever = cam.isPermanentlyDenied;
          _error = cam.isPermanentlyDenied
              ? 'Cámara denegada permanentemente. Activala en Ajustes.'
              : 'Permiso de cámara denegado.';
        });
        return;
      }

      final totalUsed = await PhotoStore.countSheetPhotos(widget.sheetId);
      if (totalUsed >= kMaxPhotosTotal) {
        setState(() => _error = 'Límite de $kMaxPhotosTotal fotos por planilla.');
        return;
      }

      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _error = 'No hay cámara disponible.');
        return;
      }

      final back = cams.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );

      final ctrl = CameraController(
        back,
        ResolutionPreset.high, // calidad alta y estable
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      _controller = ctrl;
      await ctrl.initialize();
      await ctrl.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await ctrl.setFlashMode(FlashMode.off);

      if (!mounted) return;
      setState(() {}); // mostrar preview

      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      _startCountdown();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Error inicializando cámara: $e');
    }
  }

  void _startCountdown() {
    _ticker?.cancel();
    setState(() => _remaining = kSnapCountdownSec);
    HapticFeedback.mediumImpact();

    _ticker = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_remaining <= 1) {
        t.cancel();
        setState(() => _remaining = 0);
        HapticFeedback.mediumImpact();
        await _takeAndReturn();
      } else {
        setState(() => _remaining -= 1);
        HapticFeedback.selectionClick();
      }
    });
  }

  Future<void> _takeAndReturn() async {
    if (_taking) return;
    _taking = true;
    try {
      final ctrl = _controller;
      if (ctrl == null || !ctrl.value.isInitialized) {
        setState(() => _error = 'Cámara no lista.');
        _taking = false;
        return;
      }

      final shot = await ctrl.takePicture().timeout(const Duration(seconds: 8));

      final saved = await PhotoStore.saveCameraXFile(
        xfile: shot,
        sheetId: widget.sheetId,
        rowId: widget.rowId,
      );

      // Verifica persistencia antes de cerrar
      final ok = await File(saved.file.path).exists();
      if (!ok) {
        throw Exception('Archivo no quedó grabado');
      }

      // Registrar para rehidratación robusta
      CrashGuard.I.stagePhotoPath(saved.file.path);

      if (!mounted || _popped) return;
      _ticker?.cancel();
      _popped = true;
      Navigator.of(context).pop<String>(saved.file.path);
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _error = 'Tiempo de captura agotado. Intentá de nuevo.');
      _taking = false;
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Fallo al capturar/guardar: $e');
      _taking = false;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    final hasPreview = ctrl != null && ctrl.value.isInitialized;
    final counting = _remaining > 0;

    return WillPopScope(
      onWillPop: () async {
        _ticker?.cancel();
        _popped = true;
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (hasPreview) CameraPreview(ctrl),
            if (!hasPreview && _error == null)
              const Center(child: CircularProgressIndicator.adaptive()),
            if (_error != null)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                    if (_permDeniedForever)
                      const TextButton(
                        onPressed: openAppSettings,
                        child: Text('Abrir Ajustes'),
                      ),
                  ],
                ),
              ),

            // Cerrar
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  color: Colors.white70,
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _ticker?.cancel();
                    Navigator.of(context).maybePop();
                  },
                  tooltip: 'Cancelar',
                ),
              ),
            ),

            // Estado superior
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    counting ? 'Foto en $_remaining…' : (_taking ? 'Capturando…' : 'Listo'),
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
              ),
            ),

            // Overlay del temporizador
            if (counting)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black26,
                    child: Center(
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey(_remaining),
                        tween: Tween(begin: 1.0, end: 0.0),
                        duration: const Duration(seconds: 1),
                        builder: (context, v, _) => Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 140,
                              height: 140,
                              child: CircularProgressIndicator(
                                value: v,
                                strokeWidth: 8,
                                color: Colors.white,
                                backgroundColor: Colors.white24,
                              ),
                            ),
                            Text(
                              '$_remaining',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 72,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Barra inferior
            if (hasPreview && (counting || !_taking))
              SafeArea(
                minimum: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          _ticker?.cancel();
                          Navigator.of(context).maybePop();
                        },
                        icon: const Icon(Icons.close, color: Colors.white70),
                        label: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
                      ),
                      if (counting)
                        FilledButton.icon(
                          onPressed: () {
                            _ticker?.cancel();
                            setState(() => _remaining = 0);
                            _takeAndReturn();
                          },
                          icon: const Icon(Icons.camera),
                          label: const Text('Tomar ahora'),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
