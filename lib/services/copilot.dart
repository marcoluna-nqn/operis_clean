import 'package:flutter/widgets.dart';
import '../models/measurement.dart';
import '../models/sheet_meta.dart';

class CopilotVisionResult {
  final List<Measurement> rows;
  final String summary;
  CopilotVisionResult(this.rows, this.summary);
}

class Copilot {
  Copilot._();
  static final Copilot instance = Copilot._();

  Future<CopilotVisionResult?> quickScan(BuildContext ctx, {SheetMeta? into}) async {
    return CopilotVisionResult(const [], 'Copilot (stub): sin acciones.');
  }

  Future<SheetMeta> commitToSheet(SheetMeta? meta, List<Measurement> rows) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return meta ?? SheetMeta(id: now, name: 'Escaneo Copiloto', createdAt: now);
  }
}
