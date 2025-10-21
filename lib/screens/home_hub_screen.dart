import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'beta_sheet_screen.dart';

class HomeHubScreen extends StatefulWidget {
  const HomeHubScreen({super.key});
  @override
  State<HomeHubScreen> createState() => _HomeHubScreenState();
}

class _HomeHubScreenState extends State<HomeHubScreen> {
  final _searchCtrl = TextEditingController();
  List<_SheetShortcut> _recents = [];
  List<_SheetShortcut> _favorites = [];

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final sp = await SharedPreferences.getInstance();
    _recents = _decode(sp.getStringList('recents') ?? []);
    _favorites = _decode(sp.getStringList('favorites') ?? []);
    if (mounted) setState(() {});
  }

  Future<void> _saveState() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList('recents', _encode(_recents));
    await sp.setStringList('favorites', _encode(_favorites));
  }

  List<_SheetShortcut> _decode(List<String> raw) =>
      raw.map((e) => _SheetShortcut.fromString(e)).toList();
  List<String> _encode(List<_SheetShortcut> list) =>
      list.map((e) => e.asString).toList();

  void _openSheet({_SheetShortcut? shortcut}) async {
    final title = shortcut?.title.trim().isEmpty ?? true
        ? 'Bitácora'
        : shortcut!.title.trim();
    await Navigator.push(
        context,
        CupertinoPageRoute(
          builder: (_) => BetaSheetScreen(title: title),
        ));
    final item = _SheetShortcut(
      title: title,
      path: 'local://beta',
      updatedAt: DateTime.now(),
    );
    _recents.removeWhere((x) => x.path == item.path && x.title == item.title);
    _recents.insert(0, item);
    if (_recents.length > 8) _recents = _recents.take(8).toList();
    await _saveState();
    if (mounted) setState(() {});
  }

  void _toggleFavorite(_SheetShortcut s) async {
    final idx =
        _favorites.indexWhere((x) => x.path == s.path && x.title == s.title);
    if (idx >= 0) {
      _favorites.removeAt(idx);
    } else {
      _favorites.insert(0, s);
    }
    await _saveState();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Bitácora'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.pushNamed(context, '/export'),
            child: const Icon(CupertinoIcons.square_arrow_up),
          ),
          const SizedBox(width: 6),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.pushNamed(context, '/settings'),
            child: const Icon(CupertinoIcons.gear_alt),
          ),
        ]),
      ),
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: CupertinoSearchTextField(
                  controller: _searchCtrl,
                  placeholder: 'Buscar planilla…',
                  onSubmitted: (q) => _openSheet(
                    shortcut: _SheetShortcut(
                      title: q.trim().isEmpty ? 'Bitácora' : q.trim(),
                      path: 'local://beta',
                      updatedAt: DateTime.now(),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _QuickTile(
                      icon: CupertinoIcons.doc_plaintext,
                      label: 'Nueva bitácora',
                      onTap: () => _openSheet(),
                    ),
                    _QuickTile(
                      icon: CupertinoIcons.clock,
                      label: 'Abrir última',
                      onTap: () => _openSheet(
                          shortcut:
                              _recents.isNotEmpty ? _recents.first : null),
                    ),
                    _QuickTile(
                      icon: CupertinoIcons.question_circle,
                      label: 'Ayuda',
                      onTap: () =>
                          launchUrl(Uri.parse('https://example.com/help')),
                    ),
                  ],
                ),
              ),
            ),
            if (_favorites.isNotEmpty)
              SliverToBoxAdapter(
                child: _Section(
                  title: 'Favoritos',
                  child: _ShortcutList(
                    items: _favorites,
                    onOpen: _openSheet,
                    onStar: _toggleFavorite,
                    starred: (s) => _favorites
                        .any((x) => x.path == s.path && x.title == s.title),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: _Section(
                title: 'Recientes',
                trailing: _recents.isEmpty
                    ? const SizedBox.shrink()
                    : CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () async {
                          _recents.clear();
                          await _saveState();
                          if (mounted) setState(() {});
                        },
                        child: const Text('Limpiar'),
                      ),
                child: _recents.isEmpty
                    ? const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                        child: Text('Aún no hay bitácoras recientes.'),
                      )
                    : _ShortcutList(
                        items: _recents,
                        onOpen: _openSheet,
                        onStar: _toggleFavorite,
                        starred: (s) => _favorites
                            .any((x) => x.path == s.path && x.title == s.title),
                      ),
              ),
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        ),
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = CupertinoTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cs.barBackgroundColor.withOpacity(.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 10),
            Flexible(child: Text(label, style: const TextStyle(fontSize: 15))),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _ShortcutList extends StatelessWidget {
  const _ShortcutList({
    required this.items,
    required this.onOpen,
    required this.onStar,
    required this.starred,
  });
  final List<_SheetShortcut> items;
  final void Function({_SheetShortcut? shortcut}) onOpen;
  final void Function(_SheetShortcut) onStar;
  final bool Function(_SheetShortcut) starred;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final s = items[i];
        final isFav = starred(s);
        return GestureDetector(
          onTap: () => onOpen(shortcut: s),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Theme.of(context).dividerColor.withOpacity(.2)),
            ),
            child: Row(
              children: [
                const Icon(CupertinoIcons.doc_text, size: 20),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(s.subtitle, style: const TextStyle(fontSize: 12)),
                  ],
                )),
                const SizedBox(width: 8),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => onStar(s),
                  child: Icon(
                      isFav ? CupertinoIcons.star_fill : CupertinoIcons.star,
                      size: 20),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SheetShortcut {
  final String title;
  final String path; // local://beta
  final DateTime updatedAt;

  _SheetShortcut(
      {required this.title, required this.path, required this.updatedAt});

  String get subtitle {
    final ts = updatedAt.toLocal();
    String two(int x) => x.toString().padLeft(2, '0');
    return "Actualizado ${two(ts.day)}/${two(ts.month)}/${ts.year} ${two(ts.hour)}:${two(ts.minute)}";
  }

  String get asString => "$title|$path|${updatedAt.millisecondsSinceEpoch}";
  factory _SheetShortcut.fromString(String raw) {
    final p = raw.split('|');
    return _SheetShortcut(
      title: p.isNotEmpty ? p[0] : 'Bitácora',
      path: p.length > 1 ? p[1] : 'local://beta',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        p.length > 2
            ? int.tryParse(p[2]) ?? DateTime.now().millisecondsSinceEpoch
            : DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}
