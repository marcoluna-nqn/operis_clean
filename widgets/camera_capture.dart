// lib/widgets/camera_capture.dart
import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import './capture_preview.dart';

/// Captura simple in-app con `camera`.
/// Devuelve vía `Navigator.pop(context, String path)` el JPG final.
class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({
    super.key,
    this.countdownSeconds = 3, // 3..2..1
  });

  final int countdownSeconds;

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _index = 0;
  FlashMode _flash = FlashMode.off;
  bool _busy = false;
  bool _initialized = false;

  // Countdown
  int? _countdown; // null => inactivo
  Timer? _countTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countTimer?.cancel();
    _disposeController();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !_initialized) return;
    if (state == AppLifecycleState.inactive) {
      _disposeController();
    } else if (state == AppLifecycleState.resumed) {
      _createController(_cameras[_index]);
    }
  }

  Future<void> _init() async {
    // En desktop (Windows/macOS/Linux) no pedimos permiso con permission_handler.
    if (Platform.isAndroid || Platform.isIOS) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (!mounted) return;
        Navigator.of(context).pop(null);
        return;
      }
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw StateError('No se encontraron cámaras.');
      }
      final backIndex = _cameras.indexWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
      );
      _index = backIndex >= 0 ? backIndex : 0;
      await _createController(_cameras[_index]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cámara no disponible: $e\n'
                '${Platform.isWindows ? 'Verificá Privacidad > Cámara en Windows.' : ''}',
          ),
        ),
      );
      Navigator.of(context).pop(null);
    }
  }

  Future<void> _createController(CameraDescription desc) async {
    _disposeController();
    final controller = CameraController(
      desc,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = controller;
    try {
      await controller.initialize();
      _initialized = true;
      await controller.setFlashMode(_flash);
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      _initialized = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al iniciar cámara: $e')),
      );
      Navigator.of(context).pop(null);
    }
  }

  void _disposeController() {
    _initialized = false;
    final c = _controller;
    _controller = null;
    c?.dispose();
  }

  Future<String?> _shoot() async {
    if (_busy) return null;
    final controller = _controller;
    if (controller == null || !_initialized || !controller.value.isInitialized) {
      return null;
    }
    setState(() => _busy = true);
    try {
      final x = await controller.takePicture();
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = File(p.join(dir.path, 'IMG_$stamp.jpg'));
      await File(x.path).copy(file.path);
      return file.path;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error de captura: $e')),
        );
      }
      return null;
    } finally {
      if (!mounted) return null;
      setState(() => _busy = false);
    }
  }

  // ===== Countdown =====
  void _startCountdown() {
    if (_busy || _countdown != null) return;
    setState(() => _countdown = widget.countdownSeconds);

    _countTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) return;
      await SystemSound.play(SystemSoundType.click);
      setState(() {
        if (_countdown != null && _countdown! > 1) {
          _countdown = _countdown! - 1;
        } else {
          t.cancel();
          _countdown = null;
        }
      });

      if (_countdown == null) {
        final path = await _shoot();
        if (!mounted) return;
        if (path == null) return;

        final result = await Navigator.of(context).push<String?>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (ctx) => CapturePreview(
              filePath: path,
              onAccept: () => Navigator.of(ctx).pop(path),
              onRetake: () => Navigator.of(ctx).pop(null),
            ),
          ),
        );

        if (!mounted) return;
        if (result == null) return; // retomar
        Navigator.of(context).pop(result);
      }
    });
  }

  void _cancelCountdown() {
    _countTimer?.cancel();
    _countTimer = null;
    if (_countdown != null) {
      setState(() => _countdown = null);
    }
  }
  // =====================

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    final modes = [FlashMode.off, FlashMode.auto, FlashMode.always, FlashMode.torch];
    final next = modes[(modes.indexOf(_flash) + 1) % modes.length];
    try {
      await controller.setFlashMode(next);
      if (!mounted) return;
      setState(() => _flash = next);
    } catch (_) {}
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    _index = (_index + 1) % _cameras.length;
    await _createController(_cameras[_index]);
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller != null && _controller!.value.isInitialized;

    Widget countdownOverlay() {
      if (_countdown == null) return const SizedBox.shrink();
      return Positioned.fill(
        child: GestureDetector(
          onTap: _cancelCountdown,
          child: Container(
            color: Colors.black45,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_countdown!}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 96,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Tocar para cancelar',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (ready)
              Center(child: CameraPreview(_controller!))
            else
              const Center(child: CircularProgressIndicator()),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(null),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.cameraswitch, color: Colors.white),
                    onPressed: _switchCamera,
                  ),
                  IconButton(
                    icon: Icon(
                      _flash == FlashMode.off
                          ? Icons.flash_off
                          : _flash == FlashMode.auto
                          ? Icons.flash_auto
                          : _flash == FlashMode.torch
                          ? Icons.highlight
                          : Icons.flash_on,
                      color: Colors.white,
                    ),
                    onPressed: _toggleFlash,
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    // Tap: inicia o cancela la cuenta regresiva
                    if (_countdown != null) {
                      _cancelCountdown();
                    } else {
                      _startCountdown();
                    }
                  },
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(
                          (_busy || _countdown != null) ? 0.55 : 1.0,
                        ),
                        width: 4,
                      ),
                    ),
                    child: _busy
                        ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                        : null,
                  ),
                ),
              ),
            ),
            // Overlay 3..2..1
            countdownOverlay(),
          ],
        ),
      ),
    );
  }
}
