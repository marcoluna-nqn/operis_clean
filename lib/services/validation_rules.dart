import '../models/measurement.dart';

abstract class Rule {
  String? validate(Measurement m);
}

class RangeRule extends Rule {
  RangeRule(this.field, this.min, this.max, {this.label});
  final String field;
  final double min;
  final double max;
  final String? label;

  @override
  String? validate(Measurement m) {
    double? v;
    switch (field) {
      case 'ohm1m':
        v = m.ohm1m;
        break;
      case 'ohm3m':
        v = m.ohm3m;
        break;
      case 'lat':
        v = m.latitude;
        break;
      case 'lng':
        v = m.longitude;
        break;
    }
    if (v == null) return null;
    if (v < min || v > max) {
      return '${label ?? field} fuera de rango [$min, $max]';
    }
    return null;
  }
}

class MaxLenRule extends Rule {
  MaxLenRule(this.field, this.max, {this.label});
  final String field;
  final int max;
  final String? label;

  @override
  String? validate(Measurement m) {
    String v = '';
    switch (field) {
      case 'progresiva':
        v = m.progresiva;
        break;
      case 'obs':
        v = m.observations;
        break;
    }
    if (v.length > max) return '${label ?? field} excede $max caracteres';
    return null;
  }
}

class RequiredRule extends Rule {
  RequiredRule(this.field, {this.label});
  final String field;
  final String? label;

  @override
  String? validate(Measurement m) {
    String? v;
    switch (field) {
      case 'progresiva':
        v = m.progresiva;
        break;
    }
    if (v == null || v.trim().isEmpty) {
      return '${label ?? field} es obligatorio';
    }
    return null;
  }
}

class RuleSet {
  RuleSet(this.rules);
  final List<Rule> rules;

  List<String> validateRow(Measurement m) {
    final errs = <String>[];
    for (final r in rules) {
      final e = r.validate(m);
      if (e != null) errs.add(e);
    }
    return errs;
  }
}

RuleSet defaultRules() => RuleSet([
      RequiredRule('progresiva', label: 'Progresiva'),
      RangeRule('ohm1m', 0, 1e6, label: '1 m (ÃƒÆ’Ã…Â½Ãƒâ€šÃ‚Â©)'),
      RangeRule('ohm3m', 0, 1e6, label: '3 m (ÃƒÆ’Ã…Â½Ãƒâ€šÃ‚Â©)'),
      MaxLenRule('obs', 200, label: 'Observaciones'),
      RangeRule('lat', -90, 90, label: 'Latitud'),
      RangeRule('lng', -180, 180, label: 'Longitud'),
    ]);
