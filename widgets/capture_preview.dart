// lib/widgets/capture_preview.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CapturePreview extends StatefulWidget {
  const CapturePreview({
    super.key,
    required this.filePath,
    required this.onAccept,
    required this.onRetake,
  });

  final String filePath;
  final VoidCallback onAccept;
  final VoidCallback onRetake;

  @override
  State<CapturePreview> createState() => _CapturePreviewState();
}

class _CapturePreviewState extends State<CapturePreview> {
  bool ok = false;

  Future<void> _retake() async {
    try {
      final f = File(widget.filePath);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
    if (mounted) widget.onRetake();
  }

  Future<void> _accept() async {
    setState(() => ok = true);
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 220));
    if (mounted) widget.onAccept();
  }

  @override
  Widget build(BuildContext context) {
    final img = File(widget.filePath);

    return WillPopScope(
      onWillPop: () async {
        await _retake(); // borrar si sale con “back”
        return false;
      },
      child: Shortcuts(
        shortcuts: <LogicalKeySet, Intent>{
          LogicalKeySet(LogicalKeyboardKey.escape): const _RetakeIntent(),
          LogicalKeySet(LogicalKeyboardKey.enter): const _AcceptIntent(),
          LogicalKeySet(LogicalKeyboardKey.numpadEnter): const _AcceptIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _RetakeIntent: CallbackAction<_RetakeIntent>(onInvoke: (_) {
              _retake();
              return null;
            }),
            _AcceptIntent: CallbackAction<_AcceptIntent>(onInvoke: (_) {
              _accept();
              return null;
            }),
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                Positioned.fill(
                  child: img.existsSync()
                      ? Image.file(
                    img,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  )
                      : const Center(
                    child: Text(
                      'Imagen no disponible',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                HapticFeedback.selectionClick();
                                await _retake();
                              },
                              icon: const Icon(Icons.close),
                              label: const Text('Retomar'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _accept,
                              icon: const Icon(Icons.check),
                              label: const Text('Usar'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  ignoring: true,
                  child: AnimatedOpacity(
                    opacity: ok ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Center(
                      child: AnimatedScale(
                        scale: ok ? 1 : .7,
                        duration: const Duration(milliseconds: 180),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(.35),
                            borderRadius: BorderRadius.circular(48),
                          ),
                          child: const Icon(
                            Icons.check_circle,
                            size: 72,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AcceptIntent extends Intent {
  const _AcceptIntent();
}

class _RetakeIntent extends Intent {
  const _RetakeIntent();
}
