// lib/screens/note_screen.dart
import 'package:flutter/material.dart';

class NoteScreen extends StatefulWidget {
  final ValueChanged<String> onTextSubmitted;
  const NoteScreen({super.key, required this.onTextSubmitted});

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onTextSubmitted(text);
    _controller.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null, // multilÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â­nea
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'EscribÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â­ tu nota',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send),
              tooltip: 'Enviar',
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
