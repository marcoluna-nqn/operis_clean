// lib/core/feel.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Feel {
  static void tap() => HapticFeedback.selectionClick();
  static void success() => HapticFeedback.lightImpact();
  static void error() => HapticFeedback.heavyImpact();

  static Future<void> flash(
      BuildContext context, {
        String? text,
        IconData icon = Icons.check_rounded,
        Duration showFor = const Duration(milliseconds: 900),
      }) async {
    final cs = Theme.of(context).colorScheme;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final entry = OverlayEntry(builder: (ctx) {
      final width = MediaQuery.sizeOf(ctx).width;
      return IgnorePointer(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 160),
              builder: (ctx, v, child) => Opacity(
                opacity: v,
                child: Transform.translate(
                  offset: Offset(0, (1 - v) * -12),
                  child: child,
                ),
              ),
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                constraints: BoxConstraints(
                  // evita overflow en pantallas angostas
                  maxWidth: width - 26, // margen + borde
                ),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.90),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 12)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: cs.primary),
                    if (text != null && text.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          text,
                          maxLines: 1,
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
        ),
      );
    });

    overlay.insert(entry);
    success();
    await Future.delayed(showFor);
    // Si ya se removió por cualquier motivo, ignorá.
    try {
      entry.remove();
    } catch (_) {}
  }
}
