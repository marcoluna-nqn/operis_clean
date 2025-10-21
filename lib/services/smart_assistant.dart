// lib/services/smart_assistant.dart
import '../models/measurement.dart';

/// Contexto que recibe la IA al editar una celda
class AiCellContext {
  AiCellContext({
    required this.sheetId,
    required this.rowIndex,
    required this.columnName,
    required this.rawInput,
    required this.rows,
  });

  final String sheetId;
  final int rowIndex;
  final String columnName;
  final dynamic rawInput;
  final List<Measurement> rows;
}

/// Resultado de la IA
class AiResult {
  AiResult._(this.ok, this.value, this.hint, this.error);

  final bool ok;
  final dynamic value;
  final String? hint;
  final String? error;

  static AiResult accept(dynamic value, {String? hint}) =>
      AiResult._(true, value, hint, null);

  static AiResult reject(String error) => AiResult._(false, null, null, error);
}

/// Contrato de cualquier asistente IA
abstract class GridnoteAssistant {
  Future<AiResult> transform(AiCellContext ctx);
  void learn(Measurement m);
}
