// lib/screens/planilla_photo_page.dart
import 'package:flutter/material.dart';

class PlanillaPhotoPage extends StatelessWidget {
  final String planillaId;
  final String rowId;
  const PlanillaPhotoPage({super.key, required this.planillaId, required this.rowId});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Fotos de la fila')),
    body: Center(child: Text('Planilla: $planillaId | Fila: $rowId')),
  );
}
