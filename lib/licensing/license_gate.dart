// lib/licensing/license_gate.dart
import 'package:flutter/material.dart';
import 'license_manager.dart' as lm;

typedef _SubmitFn = Future<bool> Function(String code);

class LicenseGate extends StatefulWidget {
  final Widget child;
  final bool showBannerWhenActive;
  final GlobalKey<NavigatorState>? navigatorKey;

  const LicenseGate({
    super.key,
    required this.child,
    this.showBannerWhenActive = true,
    this.navigatorKey,
  });

  @override
  State<LicenseGate> createState() => _LicenseGateState();
}

class _LicenseGateState extends State<LicenseGate> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final manager = lm.LicenseManager.instance;
    final state = manager.state;

    final isExpired = state.status == lm.LicenseStatus.expired ||
        state.status == lm.LicenseStatus.invalid;

    if (isExpired) {
      return _ExpiredScreen(
        daysLeft: manager.daysLeft,
        busy: _busy,
        onSubmit: (code) async {
          setState(() => _busy = true);
          final ok = await manager.applyLicense(code);
          if (mounted) setState(() => _busy = false);
          if (!mounted) return ok;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ok ? 'Licencia aplicada' : 'Licencia inválida')),
          );
          if (ok) setState(() {}); // fuerza rebuild
          return ok;
        },
      );
    }

    final content = widget.child;
    if (!widget.showBannerWhenActive) return content;

    // Mostrar banner sólo en los últimos 3 días de prueba
    final showTrialBanner =
        state.status == lm.LicenseStatus.trial && manager.daysLeft <= 3;
    if (!showTrialBanner) return content;

    return Stack(
      children: [
        content,
        Positioned(
          left: 12,
          right: 12,
          bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
          child: SafeArea(
            top: false,
            child: _TrialBanner(
              daysLeft: manager.daysLeft,
              onEnterLicense: () async {
                await showLicenseSheet(
                  context,
                  navigatorKey: widget.navigatorKey,
                );
                if (mounted) setState(() {}); // refrescar luego de activar
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _TrialBanner extends StatelessWidget {
  final int daysLeft;
  final VoidCallback onEnterLicense;
  const _TrialBanner({required this.daysLeft, required this.onEnterLicense});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.amber.shade800,
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        title: Text(
          'Versión de prueba: $daysLeft día(s) restante(s)',
          style: const TextStyle(color: Colors.white),
        ),
        trailing: TextButton(
          onPressed: onEnterLicense,
          child: const Text('Ingresar licencia', style: TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}

class _ExpiredScreen extends StatelessWidget {
  final int daysLeft;
  final _SubmitFn onSubmit;
  final bool busy;
  const _ExpiredScreen({required this.daysLeft, required this.onSubmit, required this.busy});

  @override
  Widget build(BuildContext context) {
    final ctrl = TextEditingController();

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (ctx, _) {
            final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
            return SingleChildScrollView(
              padding: EdgeInsets.only(bottom: bottomInset + 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_clock, size: 64),
                        const SizedBox(height: 12),
                        const Text(
                          'Período de prueba finalizado',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Ingresá una licencia para continuar.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: ctrl,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => onSubmit(ctrl.text),
                          decoration: const InputDecoration(
                            labelText: 'Código de licencia (BN2...)',
                            border: OutlineInputBorder(),
                          ),
                          textCapitalization: TextCapitalization.characters,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: busy ? null : () => onSubmit(ctrl.text),
                            child: busy
                                ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                                : const Text('Validar y continuar'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {},
                          child: const Text('Ver planes / Contacto'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Bottom sheet para pegar/aplicar la licencia.
Future<void> showLicenseSheet(
    BuildContext context, {
      GlobalKey<NavigatorState>? navigatorKey,
    }) async {
  final ctrl = TextEditingController();
  bool applying = false;

  final ok = await showModalBottomSheet<bool>(
    context: navigatorKey?.currentContext ?? context,
    useRootNavigator: navigatorKey != null,
    isScrollControlled: true,
    builder: (ctx) {
      final bottom = MediaQuery.of(ctx).viewInsets.bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
        child: StatefulBuilder(
          builder: (ctx, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Ingresar licencia', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  hintText: 'BN2.xxxxx.yyyyy',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: applying
                      ? null
                      : () async {
                    setState(() => applying = true);
                    final ok = await lm.LicenseManager.instance
                        .applyLicense(ctrl.text.trim());
                    setState(() => applying = false);
                    if (ctx.mounted) Navigator.pop(ctx, ok);
                  },
                  child: applying
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Aplicar'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  if (ok == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Licencia aplicada')),
    );
  } else if (ok == false && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Licencia inválida')),
    );
  }
}
