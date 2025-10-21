import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../gate/trial_gate.dart';
import '../gate/entitlement_gate.dart';

/// Paywall premium (Android/Windows) sin fugas de datos.
/// - Animaciones suaves y layout responsivo.
/// - Botones consistentes; evita doble envío.
/// - Validación mínima del feedback; nada se imprime ni se sube.
/// - Atajos de teclado en escritorio (Ctrl+Enter para enviar, Esc cierra).
class BetaPaywall extends StatefulWidget {
  const BetaPaywall({super.key});

  @override
  State<BetaPaywall> createState() => _BetaPaywallState();
}

class _BetaPaywallState extends State<BetaPaywall> {
  bool _loading = true;
  bool _trialActive = false;
  bool _entitlementActive = false;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    setState(() => _loading = true);
    final t = await TrialGate().isTrialActive();
    final e = await EntitlementGate().hasEntitlement();
    if (!mounted) return;
    setState(() {
      _trialActive = t;
      _entitlementActive = e;
      _loading = false;
    });
  }

  Future<void> _openFeedback() async {
    final unlocked = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _FeedbackUnlockDialog(),
    );
    if (unlocked == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡Gracias por tu feedback! PRO +7 días.')),
      );
      await _refreshStatus();
    }
  }

  Future<void> _giveOneDay() async {
    await EntitlementGate().grantDays(1);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Acceso habilitado por 24 h.')),
    );
    await _refreshStatus();
    Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = _trialActive || _entitlementActive;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pro / Licencia'),
        actions: [
          IconButton(
            tooltip: 'Actualizar estado',
            onPressed: _refreshStatus,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _loading
            ? const _Skeleton()
            : Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatusCard(
                    title:
                    unlocked ? 'Acceso disponible' : 'Acceso restringido',
                    subtitle: _entitlementActive
                        ? 'Licencia activa.'
                        : _trialActive
                        ? 'Período de prueba activo.'
                        : 'Tu trial terminó. Podés desbloquear con feedback o 24 h de cortesía.',
                    unlocked: unlocked,
                  ),
                  const SizedBox(height: 16),
                  Text('Opciones',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.reviews_outlined),
                    onPressed: _openFeedback,
                    label: const Text('Dar feedback y desbloquear +7 días'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.timer_outlined),
                    onPressed: _giveOneDay,
                    label: const Text('Usar hoy (24 h) — solo beta'),
                  ),
                  const Spacer(),
                  Text(
                    'Estamos en beta. Tu feedback concreto nos ayuda a priorizar. '
                        'Los datos que escribas aquí no se envían automáticamente a ningún servidor.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.subtitle,
    required this.unlocked,
  });

  final String title;
  final String subtitle;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grad = LinearGradient(
      colors: unlocked
          ? [cs.primaryContainer, cs.primaryContainer.withValues(alpha: 0.6)]
          : [cs.surfaceContainerHigh, cs.surfaceContainerHighest],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: grad,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .35)),
        boxShadow: [
          if (unlocked)
            BoxShadow(
              color: cs.primary.withValues(alpha: .18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              unlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
              size: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(subtitle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackUnlockDialog extends StatefulWidget {
  const _FeedbackUnlockDialog();

  @override
  State<_FeedbackUnlockDialog> createState() => _FeedbackUnlockDialogState();
}

class _FeedbackUnlockDialogState extends State<_FeedbackUnlockDialog> {
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

  bool get _canSend {
    final w = _worstCtrl.text.trim();
    final b = _blockersCtrl.text.trim();
    return w.length >= 10 || b.length >= 10;
  }

  Future<void> _submit() async {
    if (!_canSend || _sending) return;
    setState(() => _sending = true);
    try {
      await EntitlementGate().grantDays(7);
      if (!mounted) return;
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final form = Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        // Ctrl+Enter
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
        const ActivateIntent(),
        // Enter
        const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
        // Esc
        const SingleActivator(LogicalKeyboardKey.escape): const DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            _submit();
            return null;
          }),
          DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) {
            if (!_sending) Navigator.pop(context, false);
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _worstCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '¿Qué NO te gustó?',
                  hintText: 'Sé brutalmente honesto/a (mín. 10 caracteres)',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _blockersCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '¿Qué te trabó?',
                  hintText: 'Ej.: exportación, dictado, cámara, etc.',
                ),
                onChanged: (_) => setState(() {}),
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
              const SizedBox(height: 8),
              Text(
                'Aviso de privacidad: lo que escribas aquí no se envía a ningún servidor. '
                    'Solo se usa para habilitar tiempo de prueba en este dispositivo.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );

    return AlertDialog(
      title: const Text('Ayudanos a mejorar'),
      content: SingleChildScrollView(child: form),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _canSend && !_sending ? _submit : null,
          icon: _sending
              ? const SizedBox(
            height: 18, width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Icon(Icons.lock_open_rounded),
          label: const Text('Enviar y desbloquear'),
        ),
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget bar([double h = 16]) => Container(
      height: h,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 84,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: cs.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 16),
              bar(), bar(), bar(32),
            ],
          ),
        ),
      ),
    );
  }
}
