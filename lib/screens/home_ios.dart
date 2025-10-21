// lib/screens/home_ios.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'settings_screen.dart'; // Ajustá si tu SettingsScreen vive en otro path.

class HomeIOS extends StatefulWidget {
  const HomeIOS({super.key});

  @override
  State<HomeIOS> createState() => _HomeIOSState();
}

class _HomeIOSState extends State<HomeIOS> {
  void _openSettings() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _openNewSheet() {
    HapticFeedback.selectionClick();
    // Reemplazá por tu flujo real de creación/selección de planilla.
    showCupertinoDialog(
      context: context,
      builder: (_) => const CupertinoAlertDialog(
        title: Text('Nueva planilla'),
        content: Text('Implementá acá tu flujo de “Nueva planilla”.'),
        actions: [
          CupertinoDialogAction(isDefaultAction: true, child: Text('OK')),
        ],
      ),
    ).then((_) {
      // Cierra el diálogo si no se cerró por acción (por compatibilidad)
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    });
  }

  void _openRecents() {
    HapticFeedback.selectionClick();
    // Reemplazá por tu pantalla real de Recientes.
    showCupertinoDialog(
      context: context,
      builder: (_) => const CupertinoAlertDialog(
        title: Text('Recientes'),
        content: Text('Implementá acá tu pantalla de “Recientes”.'),
        actions: [
          CupertinoDialogAction(isDefaultAction: true, child: Text('OK')),
        ],
      ),
    ).then((_) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const CupertinoPageScaffold(
      child: _HomeBody(),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody();

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const CupertinoSliverNavigationBar(
          largeTitle: Text('Bitácora'),
        ),
        SliverSafeArea(
          top: false,
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                CupertinoListSection.insetGrouped(
                  hasLeading: true,
                  children: [
                    CupertinoListTile(
                      leading: const Icon(CupertinoIcons.add),
                      title: const Text('Nueva planilla'),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => _open(context)._openNewSheet(),
                    ),
                    CupertinoListTile(
                      leading: const Icon(CupertinoIcons.clock),
                      title: const Text('Recientes'),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => _open(context)._openRecents(),
                    ),
                  ],
                ),
                CupertinoListSection.insetGrouped(
                  hasLeading: true,
                  children: [
                    CupertinoListTile(
                      leading: const Icon(CupertinoIcons.settings),
                      title: const Text('Ajustes'),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => _open(context)._openSettings(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Acceso a métodos del State para mantener el código ordenado.
  _HomeIOSState _open(BuildContext context) =>
      context.findAncestorStateOfType<_HomeIOSState>()!;
}
