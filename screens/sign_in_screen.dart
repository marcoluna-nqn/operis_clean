// lib/screens/sign_in_screen.dart
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

/// Editá esta lista con los correos habilitados para usar la app.
const List<String> kAllowedEmails = <String>[
  // 'empleado1@tuempresa.com',
  // 'empleado2@tuempresa.com',
];

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
          ),
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              await AuthService.signInWithGoogle(kAllowedEmails);
              // TODO: navegar a tu pantalla principal si corresponde
            } catch (e) {
              messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
            }
          },
          icon: const Icon(Icons.login),
          label: const Text('Ingresar con Google'),
        ),
      ),
    );
  }
}
