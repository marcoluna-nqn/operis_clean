// lib/services/ai/planner.dart
import 'dart:math';
import 'schemas.dart';
import 'skills.dart';

/// Orquestador: ejecuta skills, fusiona señales y devuelve RowDrafts listos.
class CopilotPlanner {
  final List<CopilotSkill> skills;
  CopilotPlanner(this.skills);

  Future<PlanOutcome> run(CopilotContext ctx) async {
    final Map<String, dynamic> bag = <String, dynamic>{};
    final List<Trace> traces = <Trace>[];

    for (final s in skills) {
      final t0 = DateTime.now();
      try {
        final out = await s.invoke(ctx);
        final conf = s.confidence(ctx, out);
        bag[s.name] = out;
        traces.add(Trace(s.name, true, conf, DateTime.now().difference(t0)));
      } catch (e) {
        traces.add(Trace(s.name, false, 0, DateTime.now().difference(t0), err: '$e'));
      }
    }

    final Map<String, dynamic> ocr  = (bag['ocr']     as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final Map<String, dynamic> objs = (bag['objects'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final Map<String, dynamic> gps  = (bag['gps']     as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final Map<String, dynamic> mem  = (bag['memory']  as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};

    final String desc = (ocr['bestLine'] ?? objs['topClass'] ?? 'Incidencia').toString();
    final double? lat = (gps['lat'] as num?)?.toDouble();
    final double? lng = (gps['lng'] as num?)?.toDouble();
    final double acc = (gps['acc'] as num?)?.toDouble() ?? 30.0;

    final RowDraft draft = RowDraft(
      descripcion: _applyAliases(desc, mem),
      lat: lat,
      lng: lng,
      accuracyM: acc,
      tags: _mergeTags(objs['tags'], ocr['tags'], mem['tags']),
    );

    final RowDraft validated = draft.validate();
    final double conf = _overallConfidence(traces, validated);
    return PlanOutcome(<RowDraft>[validated], conf, traces);
  }

  String _applyAliases(String text, Map<String, dynamic> mem) {
    final Map<String, String> aliases = (mem['text_aliases'] is Map)
        ? (mem['text_aliases'] as Map)
        .map((k, v) => MapEntry(k.toString(), v.toString()))
        : const <String, String>{};

    var out = text;
    for (final e in aliases.entries) {
      if (out.contains(e.key)) {
        out = out.replaceAll(e.key, e.value);
      }
    }
    return out;
  }

  List<String> _mergeTags(dynamic a, dynamic b, dynamic c) {
    final set = <String>{};
    void add(dynamic x) {
      if (x is Iterable) set.addAll(x.map((e) => e.toString()));
    }
    add(a); add(b); add(c);
    return set.take(6).toList();
  }

  double _overallConfidence(List<Trace> t, RowDraft d) {
    final ok = t.where((x) => x.ok).toList();
    final skillAvg = ok.isEmpty ? 0.0 : ok.map((x) => x.conf).fold<double>(0, (a, b) => a + b) / ok.length;
    var c = 0.6 * skillAvg;
    if (d.lat != null && d.lng != null) c += 0.2;
    if (d.tags.isNotEmpty) c += 0.1;
    if (d.descripcion.length >= 6) c += 0.1;
    return c.clamp(0, 1);
  }
}

class PlanOutcome {
  final List<RowDraft> rows;
  final double confidence; // 0–1
  final List<Trace> traces;
  PlanOutcome(this.rows, this.confidence, this.traces);
}

class Trace {
  final String skill;
  final bool ok;
  final double conf;
  final Duration dt;
  final String? err;
  Trace(this.skill, this.ok, this.conf, this.dt, {this.err});
}
