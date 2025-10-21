// Gridnote ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· ActivityTracker (ediciÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³n/teclado/toques) ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· null-safe
import 'dart:math';

class ActivityTracker {
  ActivityTracker._();
  static final ActivityTracker instance = ActivityTracker._();

  bool _isEditing = false;
  bool _isTyping = false;
  DateTime _lastPointer = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastEditChange = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastTypeChange = DateTime.fromMillisecondsSinceEpoch(0);

  // EWMA de duraciÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³n de rÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¡fagas de tipeo para ajustar la espera
  double _typingBurstAvgSec = 2.0;
  DateTime? _typingStart;

  void setEditing(bool v) {
    if (_isEditing == v) return;
    _isEditing = v;
    _lastEditChange = DateTime.now();
  }

  void setTyping(bool v) {
    if (_isTyping == v) return;
    final now = DateTime.now();
    if (v) {
      _typingStart = now;
    } else {
      if (_typingStart != null) {
        final dur = now.difference(_typingStart!).inMilliseconds / 1000.0;
        // EWMA con alpha 0.3
        _typingBurstAvgSec = 0.3 * dur + 0.7 * _typingBurstAvgSec;
      }
      _typingStart = null;
    }
    _isTyping = v;
    _lastTypeChange = now;
  }

  void pointerPulse() {
    _lastPointer = DateTime.now();
  }

  bool get isEditing => _isEditing;
  bool get isTyping => _isTyping;

  /// ÃƒÆ’Ã†â€™Ãƒâ€¦Ã‚Â¡ltima actividad relevante (toque/ediciÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³n/tipeo)
  DateTime get _lastActivity => [
        _lastPointer,
        _lastEditChange,
        _lastTypeChange,
        if (_typingStart != null) _typingStart!,
      ].reduce((a, b) => a.isAfter(b) ? a : b);

  /// Segundos de inactividad estimados
  double get idleSec {
    final now = DateTime.now();
    return max(0, now.difference(_lastActivity).inMilliseconds / 1000.0);
  }

  /// Ventana mÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â­nima de ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã¢â‚¬Å“calmaÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â para mostrar un toast sin molestar.
  double get requiredIdleSec {
    const base = 0.8; // mÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â­nimo
    final fromTyping = (_typingBurstAvgSec * 0.6).clamp(0.6, 4.0);
    final editingBias = _isEditing ? 1.2 : 0.0;
    return (base + fromTyping + editingBias).clamp(0.8, 5.0);
  }

  /// ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚ÂConviene interrupciÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³n visual ahora?
  bool get allowToastNow {
    final recentPointer =
        DateTime.now().difference(_lastPointer).inMilliseconds < 900;
    if (recentPointer) return false;
    if (_isTyping) return false;
    if (_isEditing) return idleSec >= requiredIdleSec;
    return idleSec >= requiredIdleSec * 0.7;
  }
}
