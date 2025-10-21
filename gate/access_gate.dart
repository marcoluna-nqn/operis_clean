// lib/gate/access_gate.dart
import 'package:flutter/material.dart';
import 'trial_gate.dart';
import 'entitlement_gate.dart';
import '../screens/beta_paywall.dart';

/// Punto único para validar acceso a features PRO (exportar, enviar, etc.).
class AccessGate {
  /// Devuelve true si el usuario puede usar PRO (trial activo o entitlement).
  static Future<bool> ensureCanUsePro(BuildContext context) async {
    try {
      if (await _isUnlocked()) return true;

      // Abrir paywall y esperar resultado (true si compró/desbloqueó)
      final purchased = await Navigator.of(context).push<bool?>(
        MaterialPageRoute(builder: (_) => const BetaPaywall()),
      );

      // Si el paywall retornó true, igual validamos en gates
      if (purchased == true && await _isUnlocked()) return true;

      // Rechequeo estándar por si el paywall no retornó flag
      if (await _isUnlocked()) return true;

      // A esta altura sigue bloqueado
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Acceso PRO requerido.')),
        );
      }
      return false;
    } catch (e) {
      // Falla inesperada: no bloqueamos silenciosamente
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo validar el acceso.')),
        );
      }
      return false;
    }
  }

  static Future<bool> _isUnlocked() async {
    final trialOk = await TrialGate().isTrialActive();
    final paidOk  = await EntitlementGate().hasEntitlement();
    return trialOk || paidOk;
  }
}
