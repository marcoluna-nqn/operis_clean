// lib/widgets/ocr_btn.dart
import 'package:flutter/material.dart';

class OcrBtn extends StatelessWidget {
  const OcrBtn({super.key, required this.onText});
  final ValueChanged<String> onText;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'OCR (stub)',
      icon: const Icon(Icons.text_fields),
      onPressed: () => onText('texto OCR (stub)'),
    );
  }
}
