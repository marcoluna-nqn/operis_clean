// lib/screens/camera_capture_page.dart
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({
    super.key,
    this.captureDelayMs = 700,
  });

  final int captureDelayMs;

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage>
    with WidgetsBindingObserver {
  final GlobalKey _previewKey = GlobalKey();

  CameraController? _ctrl;
  bool _initializing = true;
  bool _taking = false;
  String? _error;

  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _zoom = 1.0;
  double _zoomBaseOnScale = 1.0;

  Offset? _lastTapPx;
  DateTime? _lastTapAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCtrl();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _ctrl;
    if (ctrl == null) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _disposeCtrl();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _disposeCtrl() async {
    final ctrl = _ctrl;
    _ctrl = null;
    if (ctrl != null) {
      try {
        await ctrl.dispose();
      } catch (_) {}
    }
  }

  Future<void> _initCamera() async {
    setState(() {
      _initializing = true;
      _error = null;
    });

    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw StateError('Sin cámaras disponibles');

      final back = cams.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );

      final ctrl = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await ctrl.initialize();

      try {
        await ctrl.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {}

      try {
        await ctrl.setFlashMode(FlashMode.off);
      } catch (_) {}

      try {
        _minZoom = await ctrl.getMinZoomLevel();
        _maxZoom = math.max(_minZoom, await ctrl.getMaxZoomLevel());
        _zoom = _minZoom;
        await ctrl.setZoomLevel(_zoom);
      } catch (_) {}

      if (!mounted) {
        await ctrl.dispose();
        return;
      }

      setState(() {
        _ctrl = ctrl;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo inicializar la cámara. ($e)';
        _initializing = false;
      });
    }
  }

  Future<String> _outPath() async {
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    return p.join(dir.path, 'photo_$ts.jpg');
  }

  Future<void> _shoot() async {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (_taking) return;

    _taking = true;
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}

    try {
      if (widget.captureDelayMs > 0) {
        await Future.delayed(Duration(milliseconds: widget.captureDelayMs));
      }

      final xfile = await ctrl.takePicture();
      final dst = await _outPath();
      await File(xfile.path).copy(dst);

      if (!mounted) return;
      Navigator.of(context).pop(dst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo tomar la foto. ($e)')),
      );
    } finally {
      _taking = false;
    }
  }

  Future<void> _cycleFlash() async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    try {
      final cur = ctrl.value.flashMode;
      final next = switch (cur) {
        FlashMode.off => FlashMode.auto,
        FlashMode.auto => FlashMode.always,
        FlashMode.always => FlashMode.torch,
        _ => FlashMode.off,
      };
      await ctrl.setFlashMode(next);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  IconData _flashIcon(FlashMode m) {
    switch (m) {
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.torch:
        return Icons.highlight;
      default:
        return Icons.flash_off;
    }
  }

  // FIX: ScaleStartDetails no tiene `scale`. Solo reseteamos base.
  void _onScaleStart(ScaleStartDetails d) {
    _zoomBaseOnScale = _zoom;
  }

  Future<void> _onScaleUpdate(ScaleUpdateDetails d) async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final target = (_zoomBaseOnScale * d.scale).clamp(_minZoom, _maxZoom);
    if ((target - _zoom).abs() >= 0.01) {
      _zoom = target;
      try {
        await ctrl.setZoomLevel(_zoom);
      } catch (_) {}
      if (mounted) setState(() {});
    }
  }

  Future<void> _onTapToFocus(TapDownDetails d) async {
    final ctrl = _ctrl;
    if (ctrl == null) return;

    final rb = _previewKey.currentContext?.findRenderObject() as RenderBox?;
    if (rb == null || !rb.hasSize) return;

    final size = rb.size;
    final local = rb.globalToLocal(d.globalPosition);

    final nx = (local.dx / size.width).clamp(0.0, 1.0);
    final ny = (local.dy / size.height).clamp(0.0, 1.0);

    try {
      await ctrl.setFocusPoint(Offset(nx, ny));
    } catch (_) {}
    try {
      await ctrl.setExposurePoint(Offset(nx, ny));
    } catch (_) {}

    _lastTapPx = local;
    _lastTapAt = DateTime.now();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            if (_initializing)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else if (ctrl != null && ctrl.value.isInitialized)
                Center(
                  child: LayoutBuilder(
                    builder: (_, __) {
                      final ar = ctrl.value.aspectRatio;
                      return GestureDetector(
                        key: _previewKey,
                        behavior: HitTestBehavior.opaque,
                        onTapDown: _onTapToFocus,
                        onScaleStart: _onScaleStart,         // <-- FIX aquí
                        onScaleUpdate: _onScaleUpdate,       // usa d.scale
                        child: Stack(
                          fit: StackFit.passthrough,
                          children: [
                            AspectRatio(
                              aspectRatio: ar,
                              child: CameraPreview(ctrl),
                            ),
                            if (_lastTapPx != null &&
                                _lastTapAt != null &&
                                DateTime.now()
                                    .difference(_lastTapAt!)
                                    .inMilliseconds <
                                    1200)
                              Positioned(
                                left: _lastTapPx!.dx - 20,
                                top: _lastTapPx!.dy - 20,
                                child: IgnorePointer(
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white70,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: 'Cancelar',
                  ),
                  const Spacer(),
                  if (ctrl != null && ctrl.value.isInitialized)
                    Container(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_zoom.toStringAsFixed(2)}x',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  const SizedBox(width: 8),
                  if (ctrl != null && ctrl.value.isInitialized)
                    IconButton(
                      tooltip: 'Flash',
                      onPressed: _cycleFlash,
                      icon: Icon(
                        _flashIcon(ctrl.value.flashMode),
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),

            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom + 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap:
                    (_initializing || _error != null || _taking) ? null : _shoot,
                    child: Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: (_initializing || _error != null)
                              ? Colors.white24
                              : Colors.white,
                          width: 6,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
