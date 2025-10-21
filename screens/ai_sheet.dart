import 'package:flutter/material.dart';

class AiSheet extends StatelessWidget {
  const AiSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(4),
                )),
            const SizedBox(height: 12),
            const Text('Asistente IA',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Pronto: detecciÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â³n automÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¡tica de anomalÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â­as, relleno inteligente y reglas.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
  }
}
