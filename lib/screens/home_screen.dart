// lib/screens/home_screen.dart
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/crash_guard.dart';
import '../services/local_store.dart';
import '../services/speech_service.dart'; // ⬅️ dictado
import 'beta_sheet_screen.dart';
// ⬇️ helper del gate (sheet para ingresar licencia)
import '../licensing/license_gate.dart' as lg;

// ====== MODELO ======
class RecentSheet {
  final String id;
  final String title;
  final DateTime updatedAt;
  final bool starred;

  RecentSheet({
    required this.id,
    required this.title,
    DateTime? updatedAt,
    this.starred = false,
  }) : updatedAt = updatedAt ?? DateTime.now();

  RecentSheet copyWith({
    String? id,
    String? title,
    DateTime? updatedAt,
    bool? starred,
  }) {
    return RecentSheet(
      id: id ?? this.id,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      starred: starred ?? this.starred,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
    'starred': starred,
  };

  factory RecentSheet.fromJson(Map<String, dynamic> j) => RecentSheet(
    id: j['id'] as String,
    title: j['title'] as String,
    updatedAt:
    DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
    starred: (j['starred'] as bool?) ?? false,
  );
}

// ====== HOME ======
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _prefsKey = 'recents_v3';

  final _fmt = DateFormat('dd/MM/yyyy · HH:mm');
  final _searchCtrl = TextEditingController();

  List<RecentSheet> _all = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRecents();
    // pre-init del dictado para que el modal abra “listo”
    SpeechService.I.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      CrashGuard.I.flushNow();
    }
    if (state == AppLifecycleState.resumed) {
      _loadRecents();
    }
    super.didChangeAppLifecycleState(state);
  }

  // ---------- Storage ----------
  Future<void> _loadRecents() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefsKey);
      if (raw == null) return;

      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      final list = decoded
          .map((e) => RecentSheet.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      final byId = <String, RecentSheet>{};
      for (final s in list) {
        final prev = byId[s.id];
        if (prev == null || s.updatedAt.isAfter(prev.updatedAt)) byId[s.id] = s;
      }

      final cleaned = byId.values.toList();
      _sortStable(cleaned);
      if (!mounted) return;
      setState(() => _all = cleaned.take(200).toList());
    } catch (_) {
      final p = await SharedPreferences.getInstance();
      await p.remove(_prefsKey);
      if (!mounted) return;
      setState(() => _all = []);
    }
  }

  Future<void> _saveRecents() async {
    _sortStable(_all);
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _prefsKey,
      jsonEncode(_all.take(200).map((e) => e.toJson()).toList()),
    );
  }

  void _sortStable(List<RecentSheet> list) {
    list.sort((a, b) {
      if (a.starred != b.starred) return b.starred ? 1 : -1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }

  void _touch(RecentSheet s) {
    _all.removeWhere((x) => x.id == s.id);
    _all.insert(0, s.copyWith(updatedAt: DateTime.now()));
    _saveRecents();
    setState(() {});
  }

  Future<void> _clearAll() async {
    HapticFeedback.lightImpact();
    setState(() => _all.clear());
    await _saveRecents();
  }

  void _toggleStar(RecentSheet s) {
    HapticFeedback.selectionClick();
    final i = _all.indexWhere((x) => x.id == s.id);
    if (i == -1) return;
    _all[i] = _all[i].copyWith(starred: !_all[i].starred);
    _saveRecents();
    setState(() {});
  }

  // ---------- Crear rápida ----------
  Future<void> _quickCreate({String? title}) async {
    final id = _newId();
    final t = (title ?? '').trim().isEmpty ? 'Bitácora' : title!.trim();

    await CrashGuard.I.clear();

    final headers = List<String>.filled(5, '');
    final rows = List<RowData>.generate(
      60,
          (_) => RowData(
        cells: List<String>.filled(5, ''),
        photos: [],
        lat: null,
        lng: null,
      ),
    );
    final data = SheetData(sheetId: id, title: t, headers: headers, rows: rows);
    await LocalStore.I.save(data);

    _touch(RecentSheet(id: id, title: t));
    await _loadRecents();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('Planilla creada: $t')),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => BetaSheetScreen(
                      sheetId: id,
                      title: t,
                      skipRehydrateOnFirstOpen: true,
                    ),
                  ),
                );
              },
              child: const Text('Ver'),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ---------- Crear y entrar ----------
  Future<void> _newSheet() async {
    HapticFeedback.lightImpact();
    final title = await _askTitle(context, _titleSuggestions());
    if (title == null) return;

    final id = _newId();
    final t = title.isEmpty ? 'Bitácora' : title;

    await CrashGuard.I.clear();
    await LocalStore.I.delete(id);

    await Navigator.push(
      context,
      CupertinoPageRoute<void>(
        builder: (_) => BetaSheetScreen(
          sheetId: id,
          title: t,
          skipRehydrateOnFirstOpen: true,
        ),
      ),
    );

    _touch(RecentSheet(id: id, title: t));
    await _loadRecents();
  }

  Future<void> _openLast() async {
    HapticFeedback.lightImpact();
    if (_all.isEmpty) {
      await _newSheet();
      return;
    }
    final s = _all.first;
    await Navigator.push(
      context,
      CupertinoPageRoute<void>(
        builder: (_) => BetaSheetScreen(sheetId: s.id, title: s.title),
      ),
    );
    _touch(s);
    await _loadRecents();
  }

  // ----- Acciones -----
  Future<void> _help() async {
    HapticFeedback.selectionClick();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tutorial desactivado en esta beta')),
    );
  }

  Future<void> _openLicense() async {
    HapticFeedback.selectionClick();
    await lg.showLicenseSheet(context); // abre el sheet del gate
    if (!mounted) return;
    setState(() {}); // refresca estado
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final bg = dark ? Colors.black : cs.surface;

    final filtered = _query.trim().isEmpty
        ? _all
        : _all
        .where((e) => e.title.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar.large(
              backgroundColor: bg,
              elevation: 0,
              centerTitle: false,
              systemOverlayStyle:
              dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
              title: const Text('Bitácora'),
              actions: [
                // Long-press: copia el deviceId real del licenciamiento
                GestureDetector(
                  onLongPress: () async {
                    final p = await SharedPreferences.getInstance();
                    final id = p.getString('lic_device_id') ??
                        p.getString('install_id_v1') ??
                        'sin-id';
                    await Clipboard.setData(ClipboardData(text: id));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('deviceId copiado')),
                    );
                  },
                  child: IconButton(
                    tooltip: 'Ayuda',
                    onPressed: _help,
                    icon: const Icon(Icons.help_outline),
                  ),
                ),
                IconButton(
                  tooltip: 'Ingresar licencia',
                  onPressed: _openLicense,
                  icon: const Icon(Icons.vpn_key_outlined),
                ),
                IconButton(
                  tooltip: 'Limpiar recientes',
                  onPressed: _all.isEmpty ? null : _clearAll,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
                IconButton(
                  tooltip: 'Ajustes',
                  onPressed: () => Navigator.pushNamed(context, '/settings'),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
            SliverToBoxAdapter(child: _heroHeader(context)),
            SliverToBoxAdapter(child: _searchBar()),
            if (filtered.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: _EmptyStateCard(),
                ),
              )
            else
              SliverToBoxAdapter(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final s = filtered[i];
                    return _sheetTileCore(
                      s,
                      addShowcase: i == 0 && filtered.isNotEmpty,
                    );
                  },
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _newSheet,
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Nueva y abrir'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final t = await _askTitle(context, _titleSuggestions());
                    if (t == null) return;
                    await _quickCreate(title: t);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Crear rápida'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Tile (núcleo)
  Widget _sheetTileCore(RecentSheet s, {bool addShowcase = false}) {
    final cs = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey(s.id),
      background: Container(
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 18),
        child: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      secondaryBackground: Container(
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        child: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      onDismissed: (_) async {
        await LocalStore.I.delete(s.id);
        setState(() => _all.removeWhere((x) => x.id == s.id));
        await _saveRecents();
        await _loadRecents();
      },
      child: Material(
        color: cs.surface,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: .25),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: ListTile(
          onTap: () async {
            await Navigator.push(
              context,
              CupertinoPageRoute<void>(
                builder: (_) => BetaSheetScreen(sheetId: s.id, title: s.title),
              ),
            );
            _touch(s);
            await _loadRecents();
          },
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: cs.primary.withValues(alpha: .12),
            child: Icon(Icons.description_outlined, color: cs.primary),
          ),
          title: Text(
            s.title.isEmpty ? 'Sin título' : s.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: -.1,
            ),
          ),
          subtitle: Text(
            'Actualizado ${_fmt.format(s.updatedAt)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: s.starred ? 'Quitar favorito' : 'Favorito',
                onPressed: () => _toggleStar(s),
                icon: Icon(s.starred ? Icons.star : Icons.star_border),
              ),
              _tileMenu(s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tileMenu(RecentSheet s) => PopupMenuButton<String>(
    itemBuilder: (ctx) => const <PopupMenuEntry<String>>[
      PopupMenuItem(
        value: 'open',
        child: ListTile(
          leading: Icon(Icons.open_in_new),
          title: Text('Abrir'),
        ),
      ),
      PopupMenuItem(
        value: 'rename',
        child: ListTile(
          leading: Icon(Icons.drive_file_rename_outline),
          title: Text('Renombrar'),
        ),
      ),
      PopupMenuItem(
        value: 'dup',
        child: ListTile(
          leading: Icon(Icons.copy_all_outlined),
          title: Text('Duplicar'),
        ),
      ),
      PopupMenuItem(
        value: 'delete',
        child: ListTile(
          leading: Icon(Icons.delete_outline),
          title: Text('Eliminar'),
        ),
      ),
    ],
    onSelected: (v) async {
      switch (v) {
        case 'open':
          await Navigator.push(
            context,
            CupertinoPageRoute<void>(
              builder: (_) =>
                  BetaSheetScreen(sheetId: s.id, title: s.title),
            ),
          );
          _touch(s);
          await _loadRecents();
          break;
        case 'rename':
          final nt = await _askTitle(context, []);
          if (nt == null || nt.trim().isEmpty) return;
          final i = _all.indexWhere((x) => x.id == s.id);
          if (i >= 0) {
            _all[i] = _all[i].copyWith(title: nt.trim());
            await _saveRecents();
            await _loadRecents();
            setState(() {});
          }
          break;
        case 'dup':
          final newId = _newId();
          final original = await LocalStore.I.load(s.id);
          if (original != null) {
            final copy = SheetData(
              sheetId: newId,
              title: '${s.title} (copia)',
              headers: List<String>.from(original.headers),
              rows: original.rows
                  .map((r) => RowData(
                cells: List<String>.from(r.cells),
                photos: List<String>.from(r.photos),
                lat: r.lat,
                lng: r.lng,
              ))
                  .toList(),
            );
            await LocalStore.I.save(copy);
            _touch(RecentSheet(id: newId, title: copy.title));
            await _loadRecents();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Planilla duplicada')),
              );
            }
          }
          break;
        case 'delete':
          await LocalStore.I.delete(s.id);
          setState(() => _all.removeWhere((x) => x.id == s.id));
          await _saveRecents();
          await _loadRecents();
          break;
      }
    },
  );

  Widget _heroHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary.withValues(alpha: .20),
              cs.surfaceContainerHighest.withValues(alpha: .16),
            ],
          ),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: .45)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tus planillas',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -.2,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Crear rápida'),
                  onPressed: () async {
                    final t = await _askTitle(context, _titleSuggestions());
                    if (t == null) return;
                    _quickCreate(title: t);
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.edit_note, size: 18),
                  label: const Text('Nueva y abrir'),
                  onPressed: _newSheet,
                ),
                ActionChip(
                  avatar: const Icon(Icons.history, size: 18),
                  label: const Text('Abrir última'),
                  onPressed: _openLast,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
    child: CupertinoSearchTextField(
      controller: _searchCtrl,
      placeholder: 'Buscar planilla…',
      style: const TextStyle(fontSize: 16),
      onChanged: (q) => setState(() => _query = q),
    ),
  );

  Future<String?> _askTitle(
      BuildContext context, List<String> suggestions) async {
    final ctrl = TextEditingController();
    bool listening = false;
    String livePartial = '';
    double micLevel = 0.0;

    String resolveText() {
      final raw = ctrl.text.trim();
      if (raw.isNotEmpty) return raw;
      if (livePartial.trim().isNotEmpty) return livePartial.trim();
      return '';
    }

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;

        Future<void> startDictation(StateSetter setSB) async {
          if (!SpeechService.I.isAvailable) {
            await SpeechService.I.init();
            if (!SpeechService.I.isAvailable) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Dictado no disponible.')),
              );
              return;
            }
          }
          setSB(() => listening = true);
          final heard = await SpeechService.I.listenOnce(
            partial: (p) => setSB(() => livePartial = p),
            level: (v) => setSB(() => micLevel = v),
          );
          setSB(() => listening = false);
          if (heard != null && heard.isNotEmpty) {
            final base = ctrl.text.trim();
            final next = base.isEmpty ? heard : '$base $heard';
            ctrl.text = next;
            ctrl.selection = TextSelection.collapsed(offset: next.length);
          }
          setSB(() {
            livePartial = '';
            micLevel = 0.0;
          });
        }

        void accept(StateSetter setSB) {
          final text = resolveText();
          Navigator.pop(ctx, text);
        }

        return StatefulBuilder(
          builder: (ctx, setSB) {
            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.6,
                minChildSize: 0.4,
                maxChildSize: 0.95,
                builder: (_, scrollCtrl) {
                  return SingleChildScrollView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Título (opcional)',
                            style: Theme.of(ctx).textTheme.titleLarge),
                        const SizedBox(height: 10),
                        CupertinoTextField(
                          controller: ctrl,
                          autofocus: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => accept(setSB),
                          placeholder: listening && livePartial.isNotEmpty
                              ? '… $livePartial'
                              : 'Ej: Catódica Norte',
                          decoration: const BoxDecoration(), // Material border via decoration abajo
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        const SizedBox(height: 8),
                        _MicWaveAndGlow(level: micLevel, listening: listening),
                        const SizedBox(height: 10),
                        Text(
                          'Escribí un título, dictalo o tocá una sugerencia:',
                          style: Theme.of(ctx)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        if (suggestions.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: suggestions
                                .map(
                                  (s) => ActionChip(
                                label:
                                Text(s, overflow: TextOverflow.ellipsis),
                                onPressed: () {
                                  ctrl.text = s;
                                  ctrl.selection =
                                      TextSelection.collapsed(
                                          offset: ctrl.text.length);
                                  FocusScope.of(ctx).unfocus();
                                },
                              ),
                            )
                                .toList(),
                          ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Omitir'),
                            ),
                            const Spacer(),
                            IconButton.filledTonal(
                              tooltip: listening ? 'Grabando…' : 'Dictar',
                              onPressed:
                              listening ? null : () => startDictation(setSB),
                              icon: Icon(listening ? Icons.mic : Icons.mic_none),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () => accept(setSB),
                              child: const Text('Continuar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  List<String> _titleSuggestions() => const [
    'Catódica Norte',
    'Inspección línea 12”',
    'Parada compresor GP-3',
    'Montaje manifold 6x2',
    'Control derrames – Loc 27',
    'Ruta de pozos Zona B',
    'Ensayo H₂S',
    'Calibración caudalímetro',
    'Batería La Esperanza',
    'Plan mantenimiento semanal',
  ];

  String _newId() {
    final r = math.Random.secure();
    String hex(int n) => List<int>.generate(n, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16))
        .map((s) => s.padLeft(2, '0'))
        .join();
    return hex(16);
  }
}

// Estado vacío
class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          const Text('🗂️', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Todavía no hay bitácoras recientes.\nCreá la primera con “Crear rápida”.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Waveform + halo (igual estética que en el editor)
class _MicWaveAndGlow extends StatelessWidget {
  const _MicWaveAndGlow({required this.level, required this.listening});
  final double level; // 0..1
  final bool listening;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const base = 8.0;
    const scale = 24.0;
    const weights = [0.4, 0.7, 1.0, 0.7, 0.4];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: listening
            ? [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.25),
            blurRadius: 12 + 8 * level,
            spreadRadius: 1 + 2 * level,
          )
        ]
            : const [],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ...List.generate(weights.length, (i) {
            final h = base + scale * (level * weights[i]);
            return AnimatedContainer(
              duration: const Duration(milliseconds: 110),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 6,
              height: listening ? h : base,
              decoration: BoxDecoration(
                color: listening ? cs.primary : cs.outlineVariant,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ],
      ),
    );
  }
}
