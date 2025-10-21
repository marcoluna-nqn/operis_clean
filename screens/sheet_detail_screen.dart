// lib/screens/sheet_detail_screen.dart
import 'package:flutter/material.dart';
import '../repositories/sheets_repo.dart';

class SheetDetailScreen extends StatelessWidget {
  const SheetDetailScreen(
      {super.key, required this.repo, required this.sheetId});
  final SheetsRepo repo;
  final int sheetId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Planilla #$sheetId')),
      body: Center(child: Text('Detalle de la planilla $sheetId')),
    );
  }
}
