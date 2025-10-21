// lib/data/ai_center.dart
import 'dart:async' show Timer, unawaited;
import 'package:flutter/foundation.dart';

import '../models/measurement.dart';
import '../ai/anomaly_service.dart';
import '../ai/fill_suggester.dart';

class AiCenter extends ChangeNotifier {
  AiCenter({
    required ValueListenable<List<Measurement>> items,
    required String Function(Measurement m) keyFor,
    required AnomalyService anomalyService,
    required FillSuggester fillSuggester,
    Duration debounce = const Duration(milliseconds: 250),
  })  : _items = items,
        _keyFor = keyFor,
        _anomalySvc = anomalyService,
        _fill = fillSuggester,
        _debounceDelay = debounce;

  final ValueListenable<List<Measurement>> _items;
  final String Function(Measurement m) _keyFor;
  final AnomalyService _anomalySvc; // inyectado
  final FillSuggester _fill;        // inyectado
  final Duration _debounceDelay;

  List<AnomalyFlag> _anomalies = const <AnomalyFlag>[];
  List<FillSuggestion> _fills = const <FillSuggestion>[];

  List<AnomalyFlag> get anomalies => _anomalies;
  List<FillSuggestion> get fillSuggestions => _fills;

  Timer? _debouncer;
  bool _disposed = false;

  void init() {
    _items.addListener(_scheduleRecompute);
    _scheduleRecompute();
  }

  @override
  void dispose() {
    _items.removeListener(_scheduleRecompute);
    _debouncer?.cancel();
    _disposed = true;
    super.dispose();
  }

  void _scheduleRecompute() {
    _debouncer?.cancel();
    _debouncer = Timer(_debounceDelay, () => unawaited(_recompute()));
  }

  Future<void> _recompute() async {
    if (_disposed) return;
    try {
      final items = List<Measurement>.unmodifiable(_items.value);

      // ---- Anomalías (soporta distintos contratos de servicio) ----
      final dynamic res = await _anomalySvc.find(items);
      List<AnomalyFlag> nextFlags;

      if (res is List<AnomalyFlag>) {
        nextFlags = List<AnomalyFlag>.unmodifiable(res);
      } else if (res is Iterable) {
        nextFlags = List<AnomalyFlag>.unmodifiable(res.whereType<AnomalyFlag>());
      } else {
        // Intentamos propiedades comunes sin romper compilación
        try {
          final dynamic maybe =
              (res as dynamic).flags ??
                  (res as dynamic).anomalies ??
                  (res as dynamic).items ??
                  (res as dynamic).list;
          if (maybe is Iterable) {
            nextFlags =
            List<AnomalyFlag>.unmodifiable(maybe.whereType<AnomalyFlag>());
          } else {
            nextFlags = const <AnomalyFlag>[];
          }
        } catch (_) {
          nextFlags = const <AnomalyFlag>[];
        }
      }

      // ---- Sugerencias (síncrono) ----
      final List<FillSuggestion> nextFills =
      List<FillSuggestion>.unmodifiable(_fill.suggest(items));

      if (_disposed) return;
      _anomalies = nextFlags;
      _fills = nextFills;
      notifyListeners();
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'ai_center',
        context: ErrorDescription('while recomputing AI insights'),
      ));
    }
  }

  Future<void> refreshNow() async {
    _debouncer?.cancel();
    await _recompute();
  }

  String keyFor(Measurement m) => _keyFor(m);
}
