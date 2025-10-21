// lib/screens/company_edit_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart'; // <- Asegurate de tener la dep y pub get

// Usa SIEMPRE el modelo/servicio centralizados.
import '../services/company_info_service.dart' as ci;

class CompanyEditScreen extends StatefulWidget {
  final ci.CompanyInfo? initialInfo;
  const CompanyEditScreen({super.key, this.initialInfo});

  @override
  State<CompanyEditScreen> createState() => _CompanyEditScreenState();
}

class _CompanyEditScreenState extends State<CompanyEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nombreCtrl;
  late final TextEditingController _direccionCtrl;
  late final TextEditingController _emailCtrl;

  final ImagePicker _picker = ImagePicker();

  Color _color = Colors.cyan; // UI Color
  File? _logoFile;
  bool _saving = false;

  // ---- Conversión sin APIs deprecadas ----
  // Usa .a/.r/.g/.b (0..1), convierte a 0..255 y arma ARGB int.
  static int _colorToInt(Color c) {
    final a = (c.a * 255.0).round() & 0xff;
    final r = (c.r * 255.0).round() & 0xff;
    final g = (c.g * 255.0).round() & 0xff;
    final b = (c.b * 255.0).round() & 0xff;
    return (a << 24) | (r << 16) | (g << 8) | b;
  }

  static Color _intToColor(int v) => Color(v);

  @override
  void initState() {
    super.initState();
    final info = widget.initialInfo;
    _nombreCtrl = TextEditingController(text: info?.nombre ?? '');
    _direccionCtrl = TextEditingController(text: info?.direccion ?? '');
    _emailCtrl = TextEditingController(text: info?.email ?? '');

    // Modelo guarda int (ARGB) -> UI Color
    _color = _intToColor(info?.color ?? _colorToInt(Colors.cyan));

    final p = info?.logoPath;
    if (p != null && p.isNotEmpty) {
      final f = File(p);
      if (f.existsSync()) _logoFile = f;
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _direccionCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  String? _emailValidator(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null; // opcional
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
    return ok ? null : 'Email inválido';
  }

  Future<void> _pickLogo() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (!mounted) return;
      if (picked != null) setState(() => _logoFile = File(picked.path));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo seleccionar la imagen. Verificá permisos.'),
        ),
      );
    }
  }

  Future<void> _pickColor() async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => _ColorPickerDialog(initial: _color),
    );
    if (picked != null) setState(() => _color = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      final info = ci.CompanyInfo(
        nombre: _nombreCtrl.text.trim(),
        direccion: _direccionCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        color: _colorToInt(_color), // Color -> int ARGB (sin deprecados)
        logoPath: _logoFile?.path,
      );

      await ci.CompanyInfoService.save(info);
      if (_logoFile != null) {
        await ci.CompanyInfoService.saveLogo(_logoFile!);
      }

      if (mounted) Navigator.pop(context, info);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: no se pudo guardar.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saving = _saving;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar empresa'),
        actions: [
          IconButton(
            onPressed: saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Guardar',
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: saving,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickLogo,
                  child: CircleAvatar(
                    radius: 48,
                    backgroundImage:
                    _logoFile != null ? FileImage(_logoFile!) : null,
                    child: _logoFile == null
                        ? const Icon(Icons.add_a_photo, size: 32)
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Ingrese un nombre'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _direccionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Dirección',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: _emailValidator,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Text('Color institucional:'),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _pickColor,
                    child: CircleAvatar(backgroundColor: _color, radius: 18),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: saving ? null : _save,
                icon: saving
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.save),
                label: Text(saving ? 'Guardando...' : 'Guardar'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial});
  final Color initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late Color _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Selecciona un color'),
      content: SingleChildScrollView(
        child: BlockPicker(
          pickerColor: _current,
          onColorChanged: (c) => setState(() => _current = c),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _current),
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}
