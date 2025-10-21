import 'package:flutter/material.dart';
import 'package:bitacora/constants/colors.dart';

class WelcomeScreen extends StatelessWidget {
  final VoidCallback onStartTrial;
  const WelcomeScreen({super.key, required this.onStartTrial});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      // Usamos el fondo del tema en lugar de AppColors.backgroundDark/Light
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.grid_on, size: 72, color: AppColors.primary),
                  const SizedBox(height: 28),
                  Text(
                    '¡Bienvenido a Grid Note!',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'La herramienta profesional para tus mediciones.\n'
                    'Usá Grid Note sin límites por 1 mes gratis.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: 280,
                    child: ElevatedButton(
                      onPressed: onStartTrial,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Empezar prueba gratuita'),
                    ),
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
