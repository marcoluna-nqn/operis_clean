// lib/gate/feedback_unlock_dialog.dart
import 'package:flutter/material.dart';

// Ajustá estos imports según tu proyecto:
import 'package:bitacora/gate/trial_gate.dart';
// Si tenés un gate separado para “entitlements”, importalo.
// Si no, podés comentar EntitlementGate y usar solo TrialGate.
// alias opcional

/// Stub opcional si aún no tenés EntitlementGate.
/// Eliminá esto si ya existe tu clase real.
class EntitlementGate {
  Future<void> grantDays(int days) async {
    // Implementación real: marcar PRO por N días (persistido).
    await TrialGate().extendDays(days);
  }
}

class FeedbackUnlockDialog extends StatefulWidget {
  const FeedbackUnlockDialog({super.key, this.onSendFeedback});

  /// Callback opcional para enviar feedback (ej: a Firestore/HTTP/email).
  /// Si no se provee, se hace un “no-op” local.
  final Future<void> Function({
  required String worst,
  required String blockers,
  required String priority,
  })? onSendFeedback;

  /// Muestra el diálogo y devuelve true si se desbloqueó.
  static Future<bool> show(BuildContext context,
      {Future<void> Function({
      required String worst,
      required String blockers,
      required String priority,
      })?
      onSendFeedback}) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FeedbackUnlockDialog(onSendFeedback: onSendFeedback),
    );
    return ok == true;
  }

  @override
  State<FeedbackUnlockDialog> createState() => _FeedbackUnlockDialogState();
}

class _FeedbackUnlockDialogState extends State<FeedbackUnlockDialog> {
  final _worstCtrl = TextEditingController();
  final _blockersCtrl = TextEditingController();
  String _priority = 'Alta';
  bool _sending = false;

  @override
  void dispose() {
    _worstCtrl.dispose();
    _blockersCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final worst = _worstCtrl.text.trim();
      final blockers = _blockersCtrl.text.trim();
      final priority = _priority;

      // 1) Enviar feedback (si hay callback)
      if (widget.onSendFeedback != null) {
        await widget.onSendFeedback!(
          worst: worst,
          blockers: blockers,
          priority: priority,
        );
      } else {
        // “no-op” por defecto
        // ignore: avoid_print
        print('[Feedback] worst="$worst" | blockers="$blockers" | prio=$priority');
      }

      // 2) Recompensa: +7 días
      await EntitlementGate().grantDays(7);
      // Alternativa si preferís trabajar sobre el trial directamente:
      // await TrialGate().extendDays(7);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡Gracias! Desbloqueado por 7 días.')),
      );
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo enviar. Probá de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ayudanos a mejorar'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _worstCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '¿Qué NO te gustó?',
                hintText: 'Sé brutalmente honesto/a',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _blockersCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '¿Qué te trabó?',
                hintText: 'Ej: exportación, dictado, cámara, etc.',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _priority,
              items: const [
                DropdownMenuItem(value: 'Alta', child: Text('Prioridad alta')),
                DropdownMenuItem(value: 'Media', child: Text('Prioridad media')),
                DropdownMenuItem(value: 'Baja', child: Text('Prioridad baja')),
              ],
              onChanged: (v) => setState(() => _priority = v ?? 'Alta'),
              decoration: const InputDecoration(labelText: 'Prioridad'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _sending ? null : _submit,
          child: _sending
              ? const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Text('Enviar y desbloquear'),
        ),
      ],
    );
  }
}
