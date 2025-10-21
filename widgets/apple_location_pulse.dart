// lib/widgets/apple_location_pulse.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/location_fix_coordinator.dart';
import '../services/location_service.dart';

/// Botón para capturar coordenadas con animación estilo Apple.
/// - Pulso y glow mientras adquiere.
/// - Check/close con rebote al terminar.
/// - Chip efímero con lat/lng (y precisión si está disponible).
class AppleLocationPulse extends StatefulWidget {
  const AppleLocationPulse({
    super.key,
    this.size = 64,
    this.onFix,
    this.heroTag,
    this.tooltip = 'Obtener ubicación',
    this.showChip = true,
  });

  final double size;
  final void Function(LocationFix fix)? onFix;
  final Object? heroTag;
  final String tooltip;
  final bool showChip;

  @override
  State<AppleLocationPulse> createState() => _AppleLocationPulseState();
}

class _AppleLocationPulseState extends State<AppleLocationPulse>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  late final AnimationController _ringCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  late final AnimationController _checkCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  LocationFix? _last;
  bool _busy = false;
  bool _error = false;
  bool _showChip = false;
  Timer? _chipT;

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    _checkCtrl.dispose();
    _chipT?.cancel();
    super.dispose();
  }

  Future<void> _acquire() async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() {
      _busy = true;
      _error = false;
      _showChip = false;
    });
    _ringCtrl
      ..reset()
      ..forward();

    // Desktop suele tardar un poco más y no necesita modo “adaptivo”.
    final preferAdaptive = Platform.isAndroid || Platform.isIOS;
    final timeout = preferAdaptive
        ? const Duration(seconds: 12)
        : const Duration(seconds: 20);

    try {
      final fix = await LocationFixCoordinator.instance.getFix(
        preferAdaptive: preferAdaptive,
        overallTimeout: timeout,
        onUpgrade: (b) {
          if (!mounted) return;
          setState(() => _last = b);
        },
      );

      if (!mounted) return;
      _last = fix;

      _checkCtrl
        ..reset()
        ..forward();

      HapticFeedback.lightImpact();
      widget.onFix?.call(fix);

      if (widget.showChip) {
        setState(() => _showChip = true);
        _chipT?.cancel();
        _chipT = Timer(const Duration(seconds: 3), () {
          if (!mounted) return;
          setState(() => _showChip = false);
        });
      }
    } catch (_) {
      if (!mounted) return;
      _error = true;
      _checkCtrl
        ..reset()
        ..forward();
      HapticFeedback.heavyImpact();
      // Feedback mínimo para el usuario (ej. Windows sin permisos / fix inválido).
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ubicación no disponible. Verificá permisos/GPS.'),
          duration: Duration(milliseconds: 1600),
        ),
      );
    } finally {
      if (!mounted) return;
      _busy = false;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final color = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black;
    final bg = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF111111)
        : const Color(0xFFF5F5F7);

    return Semantics(
      button: true,
      label: widget.tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Glow pulsátil.
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) {
              final t = Curves.easeInOut.transform(
                0.5 + 0.5 * math.sin(_pulseCtrl.value * 2 * math.pi),
              );
              final blur = lerpDoubleCustom(6, 18, t);
              final op = lerpDoubleCustom(0.20, 0.35, t);
              return Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  color: color.withOpacity(op),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(op),
                      blurRadius: blur,
                      spreadRadius: 1.5,
                    ),
                  ],
                ),
              );
            },
          ),
          // Botón/anillo.
          ScaleTransition(
            scale: Tween(begin: 0.9, end: 1.04)
                .chain(CurveTween(curve: Curves.easeOut))
                .animate(_ringCtrl),
            child: _ButtonCore(
              size: s,
              bg: bg,
              fg: color,
              busy: _busy,
              error: _error,
              checkCtrl: _checkCtrl,
              onTap: _acquire,
              tooltip: widget.tooltip,
              heroTag: widget.heroTag,
            ),
          ),
          // Chip con lat/lng (y precisión si existe).
          if (widget.showChip)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              top: _showChip ? -48 : -24,
              left: (s / 2) - 90,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 240),
                opacity: _showChip ? 1 : 0,
                child: (_last == null)
                    ? const SizedBox.shrink()
                    : _LatLngChip(
                  lat: _last!.latitude,
                  lng: _last!.longitude,
                  acc: _last!.accuracyMeters,
                  fg: color,
                  bg: bg,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ButtonCore extends StatelessWidget {
  const _ButtonCore({
    required this.size,
    required this.bg,
    required this.fg,
    required this.busy,
    required this.error,
    required this.checkCtrl,
    required this.onTap,
    required this.tooltip,
    required this.heroTag,
  });

  final double size;
  final Color bg;
  final Color fg;
  final bool busy;
  final bool error;
  final AnimationController checkCtrl;
  final VoidCallback onTap;
  final String tooltip;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final border = Border.all(color: fg.withOpacity(0.12), width: 1);
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [bg, bg.withOpacity(0.92)],
    );

    Widget overlayIcon() {
      return ScaleTransition(
        scale: Tween(begin: 0.6, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut))
            .animate(checkCtrl),
        child: Icon(
          error ? Icons.close_rounded : Icons.check_rounded,
          size: size * 0.44,
          color: error ? Colors.redAccent : fg,
        ),
      );
    }

    final base = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gradient,
        border: border,
        boxShadow: [
          BoxShadow(
            color: fg.withOpacity(0.10),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: busy
              ? SizedBox(
            key: const ValueKey('busy'),
            width: size * 0.42,
            height: size * 0.42,
            child: CircularProgressIndicator(strokeWidth: 2.6, color: fg),
          )
              : Icon(
            Icons.my_location_rounded,
            key: const ValueKey('idle'),
            size: size * 0.44,
            color: fg,
          ),
        ),
      ),
    );

    return Tooltip(
      message: tooltip,
      child: Hero(
        tag: heroTag ?? hashCode,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Stack(
              alignment: Alignment.center,
              children: [
                base,
                if (!busy) IgnorePointer(ignoring: true, child: overlayIcon()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LatLngChip extends StatelessWidget {
  const _LatLngChip({
    required this.lat,
    required this.lng,
    required this.fg,
    required this.bg,
    this.acc,
  });

  final double lat;
  final double lng;
  final double? acc;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: fg,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );
    final accTxt = acc == null ? '' : '  ±${acc!.toStringAsFixed(0)}m';
    return Container(
      width: 180,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fg.withOpacity(0.12), width: 1),
        boxShadow: [
          BoxShadow(
            color: fg.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Text(
        '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}$accTxt',
        textAlign: TextAlign.center,
        style: textStyle,
      ),
    );
  }
}

// Helper local para evitar importar dart:ui sólo por lerpDouble
double lerpDoubleCustom(double a, double b, double t) => a + (b - a) * t;
