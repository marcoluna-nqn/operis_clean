// lib/screens/sheets_hub_screen.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/sheet_meta.dart';
import '../services/sheet_registry.dart';

class SheetsHubScreen extends StatefulWidget {
  const SheetsHubScreen({super.key});

  @override
  State<SheetsHubScreen> createState() => _SheetsHubScreenState();
}

class _SheetsHubScreenState extends State<SheetsHubScreen> {
  final TextEditingController _search = TextEditingController();
  List<SheetMeta> _all = const [];
  bool _loading = true;

  // Calendario
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final raw = await SheetRegistry.instance.getAllSorted();
    final list = _toMetaList(raw)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)); // últimos primero
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = false;
    });
  }

  /// Normaliza cualquier lista (SheetMeta/Sheet/map) a `List<SheetMeta>`.
  /// Asumimos que `SheetMeta.createdAt` es `int` (epoch-ms) y `id` es `int`.
  List<SheetMeta> _toMetaList(dynamic raw) {
    if (raw is List<SheetMeta>) return List<SheetMeta>.from(raw);

    int parseEpochMs(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is DateTime) return v.millisecondsSinceEpoch;
      if (v is String) {
        final asInt = int.tryParse(v);
        if (asInt != null) return asInt;
        final dt = DateTime.tryParse(v);
        if (dt != null) return dt.millisecondsSinceEpoch;
      }
      return DateTime.now().millisecondsSinceEpoch;
    }

    int parseId(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    if (raw is List) {
      return raw.map<SheetMeta>((e) {
        if (e is SheetMeta) return e;

        final d = e as dynamic;
        final idRaw = d?.id ?? d?['id'];
        final nameStr = (d?.name ?? d?['name'] ?? '(sin nombre)').toString();
        final createdMs = parseEpochMs(d?.createdAt ?? d?['createdAt']);

        return SheetMeta(
          id: parseId(idRaw), // <-- siempre int
          name: nameStr,
          createdAt: createdMs, // int epoch-ms
        );
      }).toList();
    }

    return const <SheetMeta>[];
  }

  // -------- Helpers --------
  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _fromMs(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

  List<SheetMeta> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((m) {
      final name = m.name.toLowerCase();
      final idStr = m.id.toString().toLowerCase();
      return name.contains(q) || idStr.contains(q);
    }).toList();
  }

  Map<DateTime, int> _countByDayForMonth(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    final map = <DateTime, int>{};
    for (final m in _all) {
      final d = _dateOnly(_fromMs(m.createdAt));
      if (d.isBefore(first) || d.isAfter(last)) continue;
      map[d] = (map[d] ?? 0) + 1;
    }
    return map;
  }

  List<SheetMeta> _byDay(DateTime day) {
    final only = _dateOnly(day);
    return _all.where((m) => _dateOnly(_fromMs(m.createdAt)) == only).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> _openSheet(SheetMeta meta) async {
    if (!mounted) return;
    // Placeholder: reemplazá por navegación real a tu detalle.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('Abrir planilla "${meta.name}" (implementá tu flujo).')),
    );
  }

  // -------- UI --------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final divider = theme.dividerColor;
    final surface = theme.colorScheme.surface;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Planillas'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(92),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Buscar planilla por nombre o ID…',
                      prefixIcon: const Icon(CupertinoIcons.search),
                      filled: true,
                      fillColor: surface,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: divider),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: divider),
                      ),
                    ),
                  ),
                ),
                const TabBar(
                  tabs: [
                    Tab(text: 'Lista'),
                    Tab(text: 'Calendario'),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_search.text.trim().isNotEmpty
                ? _ResultsList(items: _filtered, onOpen: _openSheet)
                : TabBarView(
                    children: [
                      _ResultsList(items: _all, onOpen: _openSheet),
                      _CalendarView(
                        month: _visibleMonth,
                        selected: _selectedDay,
                        counts: _countByDayForMonth(_visibleMonth),
                        onPrev: () => setState(() {
                          _visibleMonth = DateTime(
                              _visibleMonth.year, _visibleMonth.month - 1);
                          _selectedDay = null;
                        }),
                        onNext: () => setState(() {
                          _visibleMonth = DateTime(
                              _visibleMonth.year, _visibleMonth.month + 1);
                          _selectedDay = null;
                        }),
                        onPick: (d) => setState(() => _selectedDay = d),
                        bottom: _DayList(
                          day: _selectedDay,
                          items: _selectedDay == null
                              ? const []
                              : _byDay(_selectedDay!),
                          onOpen: _openSheet,
                        ),
                      ),
                    ],
                  )),
      ),
    );
  }
}

// ---------- Widgets ----------

class _ResultsList extends StatelessWidget {
  const _ResultsList({required this.items, required this.onOpen});
  final List<SheetMeta> items;
  final void Function(SheetMeta) onOpen;

  String _fmt(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final divider = theme.dividerColor;

    if (items.isEmpty) {
      return Center(
        child: Text(
          'Sin resultados',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: .7),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final m = items[i];
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onOpen(m),
          child: Ink(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: divider),
            ),
            child: ListTile(
              title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('Creada: ${_fmt(m.createdAt)}'),
              trailing: const Icon(CupertinoIcons.chevron_right),
            ),
          ),
        );
      },
    );
  }
}

class _CalendarView extends StatelessWidget {
  const _CalendarView({
    required this.month,
    required this.selected,
    required this.counts,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
    required this.bottom,
  });

  final DateTime month;
  final DateTime? selected;
  final Map<DateTime, int> counts; // day -> count
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onPick;
  final Widget bottom;

  String _monthTitle(DateTime m) {
    const names = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre'
    ];
    return '${names[m.month - 1]} ${m.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final divider = theme.dividerColor;

    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks = (first.weekday + 6) % 7; // Lunes=1

    final cells = <Widget>[];
    final wd = ['LU', 'MA', 'MI', 'JU', 'VI', 'SA', 'DO'];
    cells.addAll(wd.map((e) => Center(
          child: Text(e, style: const TextStyle(fontWeight: FontWeight.w700)),
        )));

    for (var i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final day = DateTime(month.year, month.month, d);
      final isSelected = selected != null &&
          day.year == selected!.year &&
          day.month == selected!.month &&
          day.day == selected!.day;
      final count = counts[DateTime(day.year, day.month, day.day)] ?? 0;

      cells.add(
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onPick(day),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primary.withValues(alpha: .15)
                  : null,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$d'),
                const SizedBox(height: 4),
                if (count > 0)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final totalCells = wd.length + leadingBlanks + daysInMonth;
    final remainder = totalCells % 7;
    if (remainder != 0) {
      for (var i = 0; i < 7 - remainder; i++) {
        cells.add(const SizedBox());
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              IconButton.filledTonal(
                onPressed: onPrev,
                icon: const Icon(CupertinoIcons.chevron_left),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Center(
                  child: Text(
                    _monthTitle(month),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: onNext,
                icon: const Icon(CupertinoIcons.chevron_right),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border.all(color: divider),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              children: cells,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: bottom),
      ],
    );
  }
}

class _DayList extends StatelessWidget {
  const _DayList({
    required this.day,
    required this.items,
    required this.onOpen,
  });
  final DateTime? day;
  final List<SheetMeta> items;
  final void Function(SheetMeta) onOpen;

  String _fmt(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (day == null) {
      return Center(
        child: Text(
          'Elegí un día',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: .7),
          ),
        ),
      );
    }
    if (items.isEmpty) {
      return Center(
        child: Text(
          'Sin planillas el ${_fmt(day!.millisecondsSinceEpoch)}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: .7),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final m = items[i];
        return ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          tileColor: theme.colorScheme.surface,
          title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('Creada: ${_fmt(m.createdAt)}'),
          trailing: const Icon(CupertinoIcons.chevron_right),
          onTap: () => onOpen(m),
        );
      },
    );
  }
}
