// lib/screens/license_activation_screen.dart
import 'package:flutter/material.dart';
import '../licensing/license_manager.dart' as lm;

class LicenseActivationScreen extends StatefulWidget {
  const LicenseActivationScreen({super.key});

  @override
  State<LicenseActivationScreen> createState() => _LicenseActivationScreenState();
}

class _LicenseActivationScreenState extends State<LicenseActivationScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _msg;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    final ok = await lm.LicenseManager.instance.applyLicense(_ctrl.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _msg = ok ? 'Licencia aplicada' : 'Licencia inválida';
    });
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final manager = lm.LicenseManager.instance;
    final state = manager.state;

    return Scaffold(
      appBar: AppBar(title: const Text('Ingresar licencia')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Estado: ${state.status.name}'),
              subtitle: Text('Días restantes: ${manager.daysLeft}'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Código de licencia',
                hintText: 'BN-YYYYMMDD-XXXXXXXX',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _apply,
              child: _busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Aplicar'),
            ),
            if (_msg != null) ...[
              const SizedBox(height: 10),
              Text(
                _msg!,
                style: TextStyle(color: _msg == 'Licencia aplicada' ? Colors.green : Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
