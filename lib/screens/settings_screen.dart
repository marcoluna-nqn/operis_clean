import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../services/prefs_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _geotag = true;
  final _qualityCtrl = TextEditingController(text: '92');
  final _prefixCtrl = TextEditingController(text: 'POZO');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qualityCtrl.dispose();
    _prefixCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _geotag = await PrefsService.getGeotagEnabled();
    _qualityCtrl.text = (await PrefsService.getImageQuality()).toString();
    _prefixCtrl.text = await PrefsService.getWellPrefix();
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final q = int.tryParse(_qualityCtrl.text) ?? 92;
    final clamped = q.clamp(50, 100);
    _qualityCtrl.text = clamped.toString();

    await PrefsService.setGeotagEnabled(_geotag);
    await PrefsService.setImageQuality(clamped);
    await PrefsService.setWellPrefix(_prefixCtrl.text.trim());

    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Listo'),
        content: const Text('Ajustes guardados'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Ajustes')),
      child: SafeArea(
        bottom: false,
        child: ListView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          children: [
            const SizedBox(height: 8),
            CupertinoListSection.insetGrouped(
              header: const Text('Campo petrolero'),
              children: [
                _CupertinoTile(
                  title: const Text('Geotag en capturas'),
                  trailing: CupertinoSwitch(
                    value: _geotag,
                    onChanged: (v) => setState(() => _geotag = v),
                  ),
                  onTap: () => setState(() => _geotag = !_geotag),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('Fotos'),
              children: [
                _CupertinoTile(
                  title: const Text('Calidad de foto (50–100)'),
                  subtitle: const Text('Afecta cámara y galería'),
                  trailing: SizedBox(
                    width: 90,
                    child: CupertinoTextField(
                      controller: _qualityCtrl,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      onChanged: (v) {
                        final n = int.tryParse(v);
                        if (n == null) return;
                        if (n < 50) _qualityCtrl.text = '50';
                        if (n > 100) _qualityCtrl.text = '100';
                        _qualityCtrl.selection = TextSelection.fromPosition(
                          TextPosition(offset: _qualityCtrl.text.length),
                        );
                        setState(() {});
                      },
                    ),
                  ),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('Bitácora'),
              children: [
                _CupertinoTile(
                  title: const Text('Prefijo de pozo'),
                  subtitle: const Text('Ej: POZO-123'),
                  trailing: SizedBox(
                    width: 160,
                    child: CupertinoTextField(
                      controller: _prefixCtrl,
                      textCapitalization: TextCapitalization.characters,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: CupertinoButton.filled(
                onPressed: _save,
                child: const Text('Guardar'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _CupertinoTile extends StatelessWidget {
  const _CupertinoTile({
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onPressed: onTap,
      child: Row(
        children: [
          Expanded(
            child: DefaultTextStyle.merge(
              style:
                  const TextStyle(fontSize: 16, color: CupertinoColors.white),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    DefaultTextStyle.merge(
                      style: const TextStyle(
                          fontSize: 13, color: CupertinoColors.systemGrey),
                      child: subtitle!,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}
