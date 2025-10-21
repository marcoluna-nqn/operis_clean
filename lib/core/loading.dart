// lib/core/loading.dart
// Loader propio. Sin flutter_easyloading.
import 'dart:async';
import 'package:flutter/material.dart';

void configureLoading() {} // compat: no-op

class LoadingOverlay {
  LoadingOverlay._();

  static OverlayEntry? _barrier;
  static OverlayEntry? _entry;
  static Timer? _delayTimer;
  static int _refCount = 0;
  static DateTime? _shownAt;

  static const _showDelay = Duration(milliseconds: 150); // evita parpadeo en tareas muy cortas
  static const _minVisible = Duration(milliseconds: 350); // sensación de estabilidad

  static void show(
      BuildContext context, {
        String? text,
      }) {
    _refCount++;
    if (_entry != null) return;

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _delayTimer?.cancel();
    _delayTimer = Timer(_showDelay, () {
      final cs = Theme.of(context).colorScheme;

      _barrier = OverlayEntry(
        builder: (_) => ModalBarrier(
          dismissible: false,
          color: Colors.black.withOpacity(0.12),
        ),
      );

      _entry = OverlayEntry(
        builder: (ctx) {
          final width = MediaQuery.sizeOf(ctx).width;
          return SafeArea(
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: width - 32,
                    minWidth: 160,
                  ),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: cs.surface.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: cs.outlineVariant.withOpacity(0.45),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                      if (text != null && text.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );

      overlay.insertAll([_barrier!, _entry!]);
      _shownAt = DateTime.now();
    });
  }

  static Future<void> hide() async {
    if (_refCount > 0) _refCount--;
    if (_refCount > 0) return;

    _delayTimer?.cancel();

    // respetá tiempo mínimo visible
    final shown = _shownAt;
    if (shown != null) {
      final remain = _minVisible - DateTime.now().difference(shown);
      if (remain > Duration.zero) {
        await Future.delayed(remain);
      }
    }

    _entry?.remove();
    _barrier?.remove();
    _entry = null;
    _barrier = null;
    _shownAt = null;
  }

  static Future<T> during<T>(
      BuildContext context,
      Future<T> future, {
        String? text,
      }) async {
    show(context, text: text);
    try {
      return await future;
    } finally {
      await hide();
    }
  }
}
