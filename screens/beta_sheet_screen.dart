// lib/screens/beta_sheet_screen.dart
// Pantalla de planillas optimizada. Look moderno, indicadores de carga,
// y ajustes de rendimiento para dispositivos de gama media como Moto G13.

import 'dart:async' show Timer, unawaited;
import 'dart:io' as io show File, Platform, Directory;
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

// XFile para content:// y bytes
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;

import '../core/feel.dart';
import '../services/crash_guard.dart';
import '../services/export_xlsx_service.dart';
import '../services/local_store.dart';
import '../services/notify_service.dart';
import '../services/speech_service.dart';
import '../services/location_service.dart';
import '../widgets/apple_location_pulse.dart';
import '../services/net.dart';
import '../services/pending_share_store.dart';
import '../shared/sheet_limits.dart'; // kMaxPhotosTotal
import 'auto_snap_camera_page.dart';

// Dimensiones base
const double kRowHeight = 56.0;
const double kHeaderHeight = 54.0;
const double kCellHPad = 10.0;

// Límites de fotos
const int kMaxPhotosPerRow = 3;

// Animaciones
const Duration kMotionFast = Duration(milliseconds: 180);
const Duration kMotion = Duration(milliseconds: 220);
const Curve kAppleCurve = Cubic(0.215, 0.61, 0.355, 1.0);

// Autosave
const Duration kAutosaveIdle = Duration(seconds: 6);
const bool kAutosaveShowToast = false;
const bool kAutosaveHaptic = false;

// HUD suave al volver de la cámara
const Duration kHudDuration = Duration(milliseconds: 1400);

// Id por defecto estable para la planilla principal
const String kDefaultSheetId = 'sheet_main';

class BetaSheetScreen extends StatefulWidget {
  const BetaSheetScreen({
    super.key,
    this.sheetId,
    this.columns = 5,
    this.initialRows = 60,
    this.title = 'Bitácora',
    this.skipRehydrateOnFirstOpen = true,
  });

  final String? sheetId;
  final int columns;
  final int initialRows;
  final String title;
  final bool skipRehydrateOnFirstOpen;

  @override
  State<BetaSheetScreen> createState() => _BetaSheetScreenState();
}

class _BetaSheetScreenState extends State<BetaSheetScreen> with TickerProviderStateMixin {
  // Datos
  late final List<String> _headers =
  List<String>.generate(widget.columns, (_) => '');
  late final List<_RowModel> _rows = List<_RowModel>.generate(
    widget.initialRows,
        (_) => _RowModel.empty(widget.columns),
  );

  // Scroll
  final _listCtrl = ScrollController();
  final _hCtrl = ScrollController();

  // Estado
  bool _cameraBusy = false;
  int? _cameraRowIndex; // fila que abrió cámara
  late String _title = widget.title;

  bool _saving = false;
  bool _dirty = false;
  Timer? _debounce;

  // Búsqueda / filtros
  String _query = '';
  bool _onlyWithPhotos = false;
  bool _onlyWithCoords = false;
  int _segIndex = 0;

  // Vista filtrada
  List<int> _visible = [];

  // GPS
  final Map<int, LocationFix> _lastFixByRow = {};

  // Persistencia
  String get _sheetKey =>
      (widget.sheetId != null && widget.sheetId!.isNotEmpty)
          ? widget.sheetId!
          : kDefaultSheetId;

  // Resaltado de filas nuevas
  final Set<int> _flashRows = <int>{};

  // Busy overlay
  int _busyOps = 0;
  String? _busyLabel;
  bool get _isBusy => _busyOps > 0;

  // HUD de retorno con miniatura
  OverlayEntry? _photoHud;
  Timer? _hudTimer;

  Future<T> _busy<T>(String label, Future<T> Function() task) async {
    if (mounted) {
      setState(() {
        _busyOps++;
        _busyLabel = label;
      });
    }
    try {
      return await task();
    } finally {
      if (mounted) {
        setState(() {
          _busyOps = _busyOps - 1;
          if (_busyOps < 0) _busyOps = 0;
          if (_busyOps == 0) _busyLabel = null;
        });
      }
    }
  }

  void _flashRow(int i) {
    _flashRows.add(i);
    if (mounted) setState(() {});
    Future.delayed(const Duration(milliseconds: 800), () {
      _flashRows.remove(i);
      if (mounted) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    CrashGuard.I.setCurrentSheet(_sheetKey);
    _attachScrollAutosave();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await SpeechService.I.init();
      final id = _sheetKey;
      final stored = await LocalStore.I.load(id);

      // ===== Carga robusta que respeta todas las columnas/filas y fotos =====
      if (stored != null && stored.sheetId == id) {
        _title = stored.title;

        final needCols = math.max(_headers.length, stored.headers.length);
        if (needCols > _headers.length) {
          _headers.addAll(List.filled(needCols - _headers.length, ''));
        }
        for (var i = 0; i < needCols; i++) {
          if (i < stored.headers.length) _headers[i] = stored.headers[i];
        }

        if (stored.rows.length > _rows.length) {
          _rows.addAll(List.generate(
            stored.rows.length - _rows.length,
                (_) => _RowModel.empty(_headers.length),
          ));
        }

        for (var r = 0; r < stored.rows.length; r++) {
          final rr = stored.rows[r];

          if (_rows[r].cells.length < _headers.length) {
            _rows[r].cells
                .addAll(List.filled(_headers.length - _rows[r].cells.length, ''));
          }
          for (var c = 0; c < _headers.length; c++) {
            _rows[r].cells[c] = (c < rr.cells.length) ? rr.cells[c] : '';
          }

          _rows[r].photos
            ..clear()
            ..addAll(rr.photos);
          _rows[r].lat = rr.lat;
          _rows[r].lng = rr.lng;
        }
      } else {
        await LocalStore.I.delete(id);
      }
      // =====================================================================

      await _rehydrateFromCrashGuard();
      CrashGuard.I.clearDraftForCurrentSheet();

      _recomputeView();
      if (mounted) setState(() {});
    });
  }

  void _attachScrollAutosave() {
    _listCtrl.addListener(() {
      CrashGuard.I.recordScrollOffset(_listCtrl.offset);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removePhotoHud();
    unawaited(_saveNow(showFeedback: false));
    _listCtrl.dispose();
    _hCtrl.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(kAutosaveIdle, () => _saveNow(showFeedback: false));
  }

  Future<void> _ensureDirtySaveNow() async {
    _dirty = true;
    await _saveNow(showFeedback: false);
  }

  Future<void> _saveNow({bool showFeedback = false}) async {
    if (!mounted || _saving || !_dirty) return;
    _saving = true;
    if (mounted) setState(() {});
    try {
      final id = _sheetKey;
      final data = SheetData(
        sheetId: id,
        title: _title,
        headers: List<String>.from(_headers),
        rows: _rows
            .map((r) => RowData(
          cells: List<String>.from(r.cells),
          photos: List<String>.from(r.photos),
          lat: r.lat,
          lng: r.lng,
        ))
            .toList(),
      );
      await LocalStore.I.save(data);
      _dirty = false;
      if (showFeedback) {
        if (kAutosaveShowToast) _toast('Guardado');
        if (kAutosaveHaptic) unawaited(HapticFeedback.lightImpact());
      }
    } catch (_) {
      // silencioso
    } finally {
      _saving = false;
      if (mounted) setState(() {});
    }
  }

  void _recomputeView() {
    final q = _query.trim().toLowerCase();
    final idx = List<int>.generate(_rows.length, (i) => i);

    if (_segIndex == 1) {
      _onlyWithPhotos = true;
      _onlyWithCoords = false;
    } else if (_segIndex == 2) {
      _onlyWithPhotos = false;
      _onlyWithCoords = true;
    } else {
      _onlyWithPhotos = false;
      _onlyWithCoords = false;
    }

    idx.removeWhere((i) {
      final r = _rows[i];
      if (_onlyWithPhotos && r.photos.isEmpty) return true;
      if (_onlyWithCoords && (r.lat == null || r.lng == null)) return true;
      if (q.isEmpty) return false;
      final inHeaders = _headers.any((h) => h.toLowerCase().contains(q));
      final inRow = r.cells.any((c) => c.toLowerCase().contains(q));
      return !(inHeaders || inRow);
    });

    _visible = idx;
  }

  // ----- Encabezados -----
  void _insertHeadersAt(List<String> names, {int? at}) {
    final pos = (at ?? _headers.length).clamp(0, _headers.length);
    setState(() {
      _headers.insertAll(pos, names);
      for (final r in _rows) {
        r.cells.insertAll(pos, List.filled(names.length, ''));
      }
      _recomputeView();
    });
    _scheduleSave();
  }

  Future<void> _addHeadersInteractive() async {
    final text = await _showEditor(
      title: 'Añadir encabezados',
      initial: '',
      placeholder: 'Uno por línea (ej.: Fecha\nEquipo\nOperario)',
    );
    if (text == null) return;

    final names =
    text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    if (names.isEmpty) {
      names.add('Col ${_headers.length + 1}');
    }

    _insertHeadersAt(names);
    Feel.tap();
    _toast(
        names.length == 1 ? 'Encabezado agregado' : '${names.length} encabezados agregados');
  }

  // ----- Filtros -----
  Future<void> _openFilters() async {
    bool photos = _onlyWithPhotos;
    bool coords = _onlyWithCoords;
    final tempCtrl = TextEditingController(text: _query);

    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSB) {
            final bottom = MediaQuery.of(ctx).viewInsets.bottom;
            final cs = Theme.of(ctx).colorScheme;
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  const Icon(Icons.filter_alt_outlined),
                  const SizedBox(width: 8),
                  Text('Filtrar / Buscar', style: Theme.of(ctx).textTheme.titleMedium),
                  const Spacer(),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Restablecer')),
                ]),
                const SizedBox(height: 8),
                CupertinoTextField(
                  controller: tempCtrl,
                  placeholder: 'Buscar texto…',
                  prefix: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.search),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  FilterChip(
                    label: const Text('Solo con fotos'),
                    selected: photos,
                    onSelected: (v) => setSB(() => photos = v),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Solo con GPS'),
                    selected: coords,
                    onSelected: (v) => setSB(() => coords = v),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        tempCtrl.clear();
                        setSB(() {
                          photos = false;
                          coords = false;
                        });
                      },
                      child: const Text('Limpiar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Aplicar'),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tip: tocá el encabezado para editar.',
                    style:
                    Theme.of(ctx).textTheme.bodySmall?.copyWith(color: cs.outline),
                  ),
                ),
              ]),
            );
          },
        );
      },
    );

    if (ok == true) {
      setState(() {
        _query = tempCtrl.text;
        _onlyWithPhotos = photos;
        _onlyWithCoords = coords;
        if (_onlyWithPhotos && !_onlyWithCoords) {
          _segIndex = 1;
        } else if (_onlyWithCoords && !_onlyWithPhotos) {
          _segIndex = 2;
        } else {
          _segIndex = 0;
        }
        _recomputeView();
      });
    }
  }

  // ----- Exportar / Guardar -----
  Future<void> _saveLocal() async {
    await _busy('Guardando…', () async {
      final headers = [..._headers, 'Fotos', 'Lat', 'Lng'];
      final rows = _rows.map((r) {
        final cells = [
          ...r.cells,
          '',
          r.lat?.toStringAsFixed(6) ?? '',
          r.lng?.toStringAsFixed(6) ?? ''
        ];
        return cells;
      }).toList();

      final imagesByRow = <int, List<String>>{};
      for (var i = 0; i < _rows.length; i++) {
        final pics = _rows[i].photos;
        if (pics.isNotEmpty) imagesByRow[i] = List<String>.from(pics);
      }

      try {
        final result = await ExportXlsxService.instance.exportToXlsx(
          headers: headers,
          rows: rows,
          imagesByRow: imagesByRow,
          imageColumnIndex: _headers.length + 1,
          sheetName: _title,
        );

        final path = result.xlsxFile.path;
        await NotifyService.I.savedXlsx(_title, path);
        _toast('Guardado en: $path');
        unawaited(HapticFeedback.lightImpact());
        unawaited(Feel.flash(context, text: 'Archivo guardado'));
      } catch (e) {
        _toast('No se pudo guardar localmente. ($e)');
      }
    });
  }

  Future<void> _exportXlsxAndShare() async {
    await _busy('Exportando XLSX…', () async {
      try {
        await _saveNow(showFeedback: false);

        final headers = [..._headers, 'Fotos', 'Lat', 'Lng'];
        final rows = _rows
            .map((r) => [
          ...r.cells,
          '',
          r.lat?.toStringAsFixed(6) ?? '',
          r.lng?.toStringAsFixed(6) ?? ''
        ])
            .toList();

        final imagesByRow = <int, List<String>>{
          for (var i = 0; i < _rows.length; i++)
            if (_rows[i].photos.isNotEmpty) i: List<String>.from(_rows[i].photos),
        };

        final result = await ExportXlsxService.instance.exportToXlsx(
          headers: headers,
          rows: rows,
          imagesByRow: imagesByRow,
          imageColumnIndex: _headers.length + 1,
          sheetName: _title,
        );

        await _shareOrQueue(
          result.shareXFile,
          subject: '$_title – Excel',
          text: 'Abrir el XLSX en Excel/Numbers.',
        );
        unawaited(HapticFeedback.lightImpact());
        unawaited(Feel.flash(context, text: 'XLSX listo'));
      } catch (e) {
        _toast('No se pudo exportar. ($e)');
      }
    });
  }

  Future<void> _exportXlsx({required bool autoOpen}) async {
    await _busy('Exportando XLSX…', () async {
      try {
        await _saveNow(showFeedback: false);

        final headers = [..._headers, 'Fotos', 'Lat', 'Lng'];
        final rows = _rows.map((r) {
          final cells = [
            ...r.cells,
            '',
            r.lat?.toStringAsFixed(6) ?? '',
            r.lng?.toStringAsFixed(6) ?? ''
          ];
          return cells;
        }).toList();

        final imagesByRow = <int, List<String>>{};
        for (var i = 0; i < _rows.length; i++) {
          final pics = _rows[i].photos;
          if (pics.isNotEmpty) imagesByRow[i] = List<String>.from(pics);
        }

        final result = await ExportXlsxService.instance.exportToXlsx(
          headers: headers,
          rows: rows,
          imagesByRow: imagesByRow,
          imageColumnIndex: _headers.length + 1,
          sheetName: _title,
        );

        if (!mounted) return;

        if (io.Platform.isAndroid) {
          if (autoOpen) {
            await OpenFilex.open(result.shareXFile.path);
          } else {
            await _shareOrQueue(
              result.shareXFile,
              subject: '$_title – Excel',
              text: 'Abrir el XLSX en Excel/Numbers.',
            );
          }
          unawaited(HapticFeedback.lightImpact());
          unawaited(Feel.flash(context, text: 'XLSX listo'));
          return;
        }

        final fileName = p.basename(result.xlsxFile.path);
        try {
          final bytes = await result.xlsxFile.readAsBytes();
          final loc = await fs.getSaveLocation(suggestedName: fileName);
          if (loc == null) {
            _toast('Cancelado.');
            return;
          }
          final String path = loc.path;
          if (path.isEmpty) {
            _toast('No se obtuvo una ruta válida.');
            return;
          }
          final xf = XFile.fromData(
            bytes,
            name: fileName,
            mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          );
          await xf.saveTo(path);
          _toast('Archivo guardado.');
          unawaited(HapticFeedback.lightImpact());
          unawaited(Feel.flash(context, text: 'Archivo guardado'));
        } catch (e) {
          _toast('No se pudo guardar. ($e)');
        }
      } catch (e) {
        _toast('No se pudo exportar. ($e)');
      }
    });
  }

  Future<void> _shareOrQueue(
      XFile xf, {
        required String subject,
        String? text,
      }) async {
    bool delivered = false;
    try {
      final params = ShareParams(files: [xf], subject: subject, text: text);
      final res = await SharePlus.instance.share(params);
      delivered = res.status == ShareResultStatus.success;
    } catch (_) {
      delivered = false;
    }

    if (!delivered) {
      if (!await Net.I.isOnline()) {
        await PendingShareStore.I.enqueueFiles([xf], subject: subject, text: text);
        _toast('Sin conexión: queda en cola para enviar automáticamente.');
      } else {
        _toast('Envío cancelado.');
      }
    }
    unawaited(HapticFeedback.lightImpact());
  }

  // ----- Filas -----
  void _addRow() {
    setState(() {
      _rows.add(_RowModel.empty(_headers.length));
      _recomputeView();
    });
    _scheduleSave();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = (_rows.length) * (kRowHeight + 1.0);
      _listCtrl.animateTo(target, duration: kMotion, curve: kAppleCurve);
      _flashRow(_rows.length - 1);
    });
    Feel.tap();
  }

  Future<void> _confirmDeleteRow(int i) async {
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    final ok = isIOS
        ? await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Eliminar fila'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            isDefaultAction: true,
            child: const Text('Cancelar'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, true),
            isDestructiveAction: true,
            child: const Text('Eliminar'),
          ),
        ],
      ),
    )
        : await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar fila'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok == true) _deleteRow(i);
  }

  void _deleteRow(int i) {
    setState(() {
      _rows.removeAt(i);
      final next = <int, LocationFix>{};
      _lastFixByRow.forEach((k, v) {
        if (k < i) {
          next[k] = v;
        } else if (k > i) {
          next[k - 1] = v;
        }
      });
      _lastFixByRow
        ..clear()
        ..addAll(next);
      _recomputeView();
    });
    _scheduleSave();
  }

  // >>> Transición fade-through a cámara + HUD suave al volver <<<
  Future<void> _addPhotoQuick(int rowIndex) async {
    if (_cameraBusy) return;
    if (!_canAddMore(rowIndex)) return;

    _cameraBusy = true;
    _cameraRowIndex = rowIndex;
    if (mounted) setState(() {});

    try {
      final path = await Navigator.of(context).push<String>(
        _fadeThroughRoute(
          AutoSnapCameraPage(
            sheetId: _sheetKey,
            rowId: rowIndex,
          ),
        ),
      );

      if (!mounted || path == null || path.isEmpty) return;

      if (_totalPhotos() >= kMaxPhotosTotal ||
          _rows[rowIndex].photos.length >= kMaxPhotosPerRow) {
        _toast('Límite de $kMaxPhotosTotal fotos por planilla alcanzado.');
        try {
          await io.File(path).delete();
        } catch (_) {}
        return;
      }

      setState(() {
        _rows[rowIndex].photos.add(path);
        _recomputeView();
      });
      CrashGuard.I.confirmPhotoLinked(path);

      await _ensureDirtySaveNow();
      if (!mounted) return;

      _showPhotoHud(path);
      unawaited(Feel.flash(context, text: 'Foto agregada'));
    } catch (e) {
      _toast('No se pudo usar la cámara. ($e)');
    } finally {
      _cameraBusy = false;
      _cameraRowIndex = null;
      if (mounted) setState(() {});
    }
  }

  int _totalPhotos() => _rows.fold<int>(0, (a, b) => a + b.photos.length);

  bool _canAddMore(int rowIndex) {
    if (_totalPhotos() >= kMaxPhotosTotal) {
      _toast('Límite de $kMaxPhotosTotal fotos por planilla alcanzado.');
      return false;
    }
    if (_rows[rowIndex].photos.length >= kMaxPhotosPerRow) {
      _toast('Máximo $kMaxPhotosPerRow por fila.');
      return false;
    }
    return true;
  }

  Future<void> _markLocationAdaptive(int rowIndex) async {
    await _busy('Obteniendo GPS…', () async {
      try {
        final fix = await LocationService.instance.getAdaptiveFix(
          config: const AdaptiveFixConfig(
            freshAge: Duration(seconds: 30),
            acceptAccuracyMeters: 25,
            fastTryTimeout: Duration(seconds: 2),
            windowForBetter: Duration(seconds: 5),
            preciseSamples: 6,
            keepBestFraction: 0.5,
          ),
          tryFullAccuracyIOS: true,
          onBetterFix: (better) {
            if (!mounted) return;
            setState(() {
              _rows[rowIndex].lat = better.latitude;
              _rows[rowIndex].lng = better.longitude;
              _lastFixByRow[rowIndex] = better;
            });
          },
        );

        if (!mounted) return;
        setState(() {
          _rows[rowIndex].lat = fix.latitude;
          _rows[rowIndex].lng = fix.longitude;
          _lastFixByRow[rowIndex] = fix;
          _recomputeView();
        });
        _scheduleSave();

        final acc =
        fix.accuracyMeters != null ? ' ±${fix.accuracyMeters!.toStringAsFixed(0)}m' : '';
        _toast('Ubicación guardada$acc.');
        unawaited(HapticFeedback.lightImpact());
      } catch (e) {
        _toast(e.toString());
      }
    });
  }

  Future<void> _showLocationActions(int rowIndex) async {
    final r = _rows[rowIndex];
    final hasCoords = (r.lat != null && r.lng != null);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.my_location_outlined),
            title: const Text('Marcar ubicación (rápido y preciso)'),
            onTap: () {
              Navigator.pop(ctx);
              unawaited(_markLocationAdaptive(rowIndex));
            },
          ),
          if (hasCoords)
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('Ver en Mapas'),
              onTap: () async {
                Navigator.pop(ctx);
                unawaited(LocationService.instance.openInMaps(
                  lat: r.lat!,
                  lng: r.lng!,
                  label: _title,
                ));
              },
            ),
        ]),
      ),
    );
  }

  Future<void> _renameSheet() async {
    final newName = await _showEditor(
      title: 'Renombrar planilla',
      initial: _title,
      placeholder: 'Nombre',
    );
    if (newName == null || newName.isEmpty) return;
    setState(() => _title = newName);
    _scheduleSave();
  }

  Future<void> _newSheetFlow() async {
    final nameCtrl = TextEditingController(text: 'Nueva planilla');
    final colsCtrl = TextEditingController(text: '5');

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSB) {
            final bottom = MediaQuery.of(ctx).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Crear planilla', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 12),
                CupertinoTextField(
                  controller: nameCtrl,
                  placeholder: 'Nombre',
                  autofocus: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                const SizedBox(height: 10),
                CupertinoTextField(
                  controller: colsCtrl,
                  placeholder: 'Columnas',
                  keyboardType: TextInputType.number,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Crear'),
                    ),
                  ),
                ]),
              ]),
            );
          },
        );
      },
    );

    if (result != true) return;

    final name =
    nameCtrl.text.trim().isEmpty ? 'Nueva planilla' : nameCtrl.text.trim();
    final cols = int.tryParse(colsCtrl.text.trim()) ?? 5;
    final safeCols = cols.clamp(1, 20);

    if (!mounted) return;
    unawaited(Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BetaSheetScreen(
          sheetId: 'sheet_${DateTime.now().millisecondsSinceEpoch}',
          title: name,
          columns: safeCols,
          initialRows: 60,
          skipRehydrateOnFirstOpen: true,
        ),
      ),
    ));
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1600),
      ),
    );
  }

  PreferredSizeWidget _buildAppBarMaterial(BuildContext context) {
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    return AppBar(
      title: Row(children: [
        const Icon(Icons.table_view_rounded, size: 20),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            _title,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
      centerTitle: isIOS,
      elevation: 1,
      scrolledUnderElevation: 2,
      actionsIconTheme: const IconThemeData(size: 22),
      actions: [
        if (_saving)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        IconButton(
          tooltip: 'Añadir encabezado',
          onPressed: _addHeadersInteractive,
          icon: const Icon(Icons.view_column),
        ),
        IconButton(
          tooltip: 'Exportar rápido',
          onPressed: _exportXlsxAndShare,
          icon: Icon(isIOS ? CupertinoIcons.share_up : Icons.ios_share),
        ),
        IconButton(
          tooltip: 'Más…',
          onPressed: isIOS ? _showActionsCupertino : _showActionsSheet,
          icon: Icon(isIOS ? CupertinoIcons.ellipsis_circle : Icons.more_horiz),
        ),
      ],
    );
  }

  Future<void> _showActionsCupertino() async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              unawaited(_exportXlsxAndShare());
            },
            child: const Text('Exportar Excel…'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              unawaited(_saveLocal());
            },
            child: const Text('Guardar local (simple)'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              unawaited(_exportXlsx(autoOpen: false));
            },
            child: const Text('Guardar como…'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              unawaited(_exportXlsxAndShare());
            },
            child: const Text('Enviar XLSX'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              unawaited(_renameSheet());
            },
            child: const Text('Renombrar'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              unawaited(_newSheetFlow());
            },
            child: const Text('Nueva planilla'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          isDefaultAction: true,
          child: const Text('Cancelar'),
        ),
      ),
    );
  }

  Future<void> _showActionsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.table_view_outlined),
            title: const Text('Exportar Excel…'),
            onTap: () {
              Navigator.pop(ctx);
              unawaited(_exportXlsxAndShare());
            },
          ),
          ListTile(
            leading: const Icon(Icons.save_alt_outlined),
            title: const Text('Guardar local (simple)'),
            onTap: () {
              Navigator.pop(ctx);
              unawaited(_saveLocal());
            },
          ),
          if (!io.Platform.isAndroid)
            ListTile(
              leading: const Icon(Icons.folder_copy_outlined),
              title: const Text('Guardar como…'),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_exportXlsx(autoOpen: false));
              },
            ),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('Enviar XLSX'),
            onTap: () {
              Navigator.pop(ctx);
              unawaited(_exportXlsxAndShare());
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: const Text('Renombrar'),
            onTap: () {
              Navigator.pop(ctx);
              unawaited(_renameSheet());
            },
          ),
          ListTile(
            leading: const Icon(Icons.post_add_outlined),
            title: const Text('Nueva planilla'),
            onTap: () {
              Navigator.pop(ctx);
              unawaited(_newSheetFlow());
            },
          ),
        ]),
      ),
    );
  }

  double _blurSigma() =>
      Theme.of(context).platform == TargetPlatform.android ? 8 : 18;

  Widget _frostedBottomBar(Widget child) {
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;

    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.40),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: child,
        ),
      ),
    );

    if (isAndroid) {
      return box;
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: _blurSigma(), sigmaY: _blurSigma()),
        child: box,
      ),
    );
  }

  // ----- Grid -----
  Widget _buildGridArea(Color divider, Color headerBg, Color rowBg) {
    return LayoutBuilder(builder: (context, constraints) {
      final int photosCol = _headers.length;
      const int totalBandCols = 5; // Fotos, Lat, Lng, GPS, Borrar
      const double minCell = 120.0;
      final double gridWidth =
      math.max(constraints.maxWidth, (photosCol + totalBandCols) * minCell);
      final double cellWidth = gridWidth / (photosCol + totalBandCols);

      final cs = Theme.of(context).colorScheme;
      final Color bandBg = cs.surfaceContainerHighest.withValues(alpha: 0.50);
      final Color headerBandBg = cs.surfaceContainerHighest.withValues(alpha: 0.80);

      final header = RepaintBoundary(
        child: Container(
          height: kHeaderHeight,
          color: headerBg,
          child: Row(children: [
            for (var c = 0; c < _headers.length; c++)
              _HeaderCell(
                width: cellWidth,
                text: _headers[c].isEmpty ? 'ABC' : _headers[c],
                divider: divider,
                onTap: () => _editHeader(c),
              ),
            _HeaderCell(
              width: cellWidth,
              text: 'Fotos',
              divider: divider,
              fill: headerBandBg,
              isBandStart: true,
            ),
            _HeaderCell(
              width: cellWidth,
              text: 'Lat',
              divider: divider,
              fill: headerBandBg,
            ),
            _HeaderCell(
              width: cellWidth,
              text: 'Lng',
              divider: divider,
              fill: headerBandBg,
            ),
            _HeaderCell(
              width: cellWidth,
              text: 'GPS',
              divider: divider,
              fill: headerBandBg,
            ),
            _HeaderCell(
              width: cellWidth,
              text: 'Borrar',
              divider: divider,
              fill: headerBandBg,
            ),
          ]),
        ),
      );

      final list = ListView.builder(
        controller: _listCtrl,
        padding: EdgeInsets.only(
          bottom: Theme.of(context).platform == TargetPlatform.iOS ? 88.0 : 0.0,
        ),
        itemExtent: kRowHeight + 1.0,
        itemCount: _visible.length,
        cacheExtent: 600.0,
        itemBuilder: (_, i) {
          final realIndex = _visible[i];
          final r = _rows[realIndex];
          final acc = _lastFixByRow[realIndex]?.accuracyMeters;

          final Color evenRow = cs.surface;
          final Color oddRow = cs.surfaceContainerHighest;
          final Color baseColor = (realIndex % 2 == 0) ? evenRow : oddRow;
          final Color hilite = _flashRows.contains(realIndex)
              ? cs.primaryContainer.withValues(alpha: 0.20)
              : baseColor;

          final rowContent = RepaintBoundary(
            child: AnimatedContainer(
              duration: kMotion,
              curve: kAppleCurve,
              color: hilite,
              child: Column(children: [
                Row(children: [
                  for (var c = 0; c < _headers.length; c++)
                    _Cell(
                      width: cellWidth,
                      divider: divider,
                      child: _CellText(
                        text: r.cells[c],
                        highlight: _query,
                        onTap: () => _editCell(realIndex, c),
                      ),
                    ),
                  _Cell(
                    width: cellWidth,
                    divider: divider,
                    fill: bandBg,
                    isBandStart: true,
                    child: _PhotosButton(
                      count: r.photos.length,
                      busy: _cameraRowIndex == realIndex,
                      onTapAdd: () => unawaited(_addPhotoQuick(realIndex)),
                      onTapManage: () => unawaited(_managePhotos(realIndex)),
                    ),
                  ),
                  _Cell(
                    width: cellWidth,
                    divider: divider,
                    fill: bandBg,
                    child: LayoutBuilder(builder: (ctx, cts) {
                      return InkWell(
                        onTap: (r.lat != null && r.lng != null)
                            ? () => unawaited(
                          LocationService.instance.openInMaps(
                            lat: r.lat!,
                            lng: r.lng!,
                            label: _title,
                          ),
                        )
                            : null,
                        borderRadius: BorderRadius.circular(8),
                        child: AnimatedSwitcher(
                          duration: kMotionFast,
                          switchInCurve: kAppleCurve,
                          switchOutCurve: kAppleCurve,
                          child: (r.lat == null)
                              ? const Text('—', key: ValueKey('lat-empty'))
                              : SizedBox(
                            width: cts.maxWidth,
                            child: _CoordPill(
                              key: ValueKey(
                                  'lat-${r.lat}-${acc?.toStringAsFixed(0)}'),
                              icon: Icons.location_pin,
                              text: [
                                r.lat!.toStringAsFixed(6),
                                if (acc != null) ' ±${acc.toStringAsFixed(0)}m'
                              ].join(),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  _Cell(
                    width: cellWidth,
                    divider: divider,
                    fill: bandBg,
                    child: LayoutBuilder(builder: (ctx, cts) {
                      return InkWell(
                        onTap: (r.lat != null && r.lng != null)
                            ? () => unawaited(
                          LocationService.instance.openInMaps(
                            lat: r.lat!,
                            lng: r.lng!,
                            label: _title,
                          ),
                        )
                            : null,
                        borderRadius: BorderRadius.circular(8),
                        child: (r.lng == null)
                            ? const Text('—')
                            : SizedBox(
                          width: cts.maxWidth,
                          child: _CoordPill(
                            icon: Icons.straighten,
                            text: r.lng!.toStringAsFixed(6),
                          ),
                        ),
                      );
                    }),
                  ),
                  _Cell(
                    width: cellWidth,
                    divider: divider,
                    fill: bandBg,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Semantics(
                          label: 'Marcar ubicación',
                          hint: 'Obtiene ubicación precisa y la guarda en la fila',
                          button: true,
                          child: GestureDetector(
                            onLongPress: () => _showLocationActions(realIndex),
                            child: AppleLocationPulse(
                              size: 40,
                              showChip: false,
                              heroTag: 'row_${realIndex}_gps',
                              tooltip: 'Marcar ubicación',
                              onFix: (f) {
                                if (!mounted) return;
                                setState(() {
                                  _rows[realIndex].lat = f.latitude;
                                  _rows[realIndex].lng = f.longitude;
                                  _lastFixByRow[realIndex] = f;
                                  _recomputeView();
                                });
                                _scheduleSave();
                                final a = f.accuracyMeters != null
                                    ? ' ±${f.accuracyMeters!.toStringAsFixed(0)}m'
                                    : '';
                                _toast('Ubicación guardada$a.');
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _Cell(
                    width: cellWidth,
                    divider: divider,
                    fill: bandBg,
                    child: Center(
                      child: OutlinedButton.icon(
                        onPressed: () => _confirmDeleteRow(realIndex),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Borrar'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: BorderSide(color: Colors.red.withValues(alpha: 0.55)),
                          padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ),
                ]),
                Divider(height: 1.0, color: divider),
              ]),
            ),
          );

          final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

          final contextual = isIOS
              ? CupertinoContextMenu(
            actions: [
              CupertinoContextMenuAction(
                onPressed: () {
                  Navigator.pop(context);
                  _showLocationActions(realIndex);
                },
                trailingIcon: CupertinoIcons.map,
                child: const Text('Ver / acciones de ubicación'),
              ),
              CupertinoContextMenuAction(
                onPressed: () {
                  Navigator.pop(context);
                  unawaited(_managePhotos(realIndex));
                },
                trailingIcon: CupertinoIcons.photo_on_rectangle,
                child: const Text('Fotos de la fila'),
              ),
              CupertinoContextMenuAction(
                onPressed: () {
                  Navigator.pop(context);
                  unawaited(_confirmDeleteRow(realIndex));
                },
                isDestructiveAction: true,
                trailingIcon: CupertinoIcons.delete,
                child: const Text('Eliminar fila'),
              ),
            ],
            child: rowContent,
          )
              : InkWell(
            onLongPress: () => _showLocationActions(realIndex),
            child: rowContent,
          );

          return contextual;
        },
      );

      return SingleChildScrollView(
        controller: _hCtrl,
        primary: false,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: gridWidth,
          child: Column(children: [
            header,
            Divider(height: 1.0, color: divider),
            Expanded(child: list),
          ]),
        ),
      );
    });
  }

  Widget _buildSegmentedFilters() {
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    final seg = CupertinoSegmentedControl<int>(
      children: const <int, Widget>{
        0: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text('Todos')),
        1: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text('Fotos')),
        2: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text('GPS')),
      },
      groupValue: _segIndex,
      onValueChanged: (v) {
        setState(() {
          _segIndex = v;
          _recomputeView();
        });
        Feel.tap();
      },
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(12, isIOS ? 8 : 12, 12, 8),
      child: LayoutBuilder(builder: (ctx, cts) {
        final narrow = cts.maxWidth < 380;
        if (narrow) {
          return Column(children: [
            seg,
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _openFilters,
              icon: const Icon(CupertinoIcons.line_horizontal_3_decrease),
              label: const Text('Buscar'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addHeadersInteractive,
              icon: const Icon(Icons.view_column),
              label: const Text('Añadir encabezado'),
            ),
          ]);
        }
        return Row(children: [
          Expanded(child: seg),
          const SizedBox(width: 10),
          Flexible(
            child: OutlinedButton.icon(
              onPressed: _openFilters,
              icon: const Icon(CupertinoIcons.line_horizontal_3_decrease),
              label: const Text('Buscar'),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: OutlinedButton.icon(
              onPressed: _addHeadersInteractive,
              icon: const Icon(Icons.view_column),
              label: const Text('Añadir encabezado'),
            ),
          ),
        ]);
      }),
    );
  }

  Widget _buildTopSummary(Color divider) {
    final total = _rows.length;
    final visibles = _visible.length;
    final withPhotos = _rows.where((r) => r.photos.isNotEmpty).length;
    final withGPS = _rows.where((r) => r.lat != null && r.lng != null).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        border: Border(bottom: BorderSide(color: divider)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _SummaryChip(icon: Icons.view_list_outlined, label: '$visibles / $total'),
          _SummaryChip(icon: Icons.photo_outlined, label: '$withPhotos con fotos'),
          _SummaryChip(icon: Icons.location_on_outlined, label: '$withGPS con GPS'),
        ],
      ),
    );
  }

  Widget _buildBusyOverlay() {
    final bg = Theme.of(context).colorScheme.surface.withValues(alpha: 0.70);
    final spinner = Theme.of(context).platform == TargetPlatform.iOS
        ? const CupertinoActivityIndicator(radius: 16)
        : const CircularProgressIndicator(strokeWidth: 3);

    return IgnorePointer(
      ignoring: false,
      child: Container(
        color: bg,
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 28, height: 28, child: Center(child: spinner)),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      _busyLabel ?? 'Cargando…',
                      style: Theme.of(context).textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
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

  Widget _withShortcuts(Widget child) {
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyN):
        const _AddRowIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyF):
        const _OpenFilterIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyE):
        const _ExportIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.delete):
        const _DeleteLastRowIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _AddRowIntent: CallbackAction<_AddRowIntent>(onInvoke: (_) {
            _addRow();
            return null;
          }),
          _OpenFilterIntent: CallbackAction<_OpenFilterIntent>(onInvoke: (_) {
            _openFilters();
            return null;
          }),
          _ExportIntent: CallbackAction<_ExportIntent>(onInvoke: (_) {
            unawaited(_exportXlsxAndShare());
            return null;
          }),
          _DeleteLastRowIntent:
          CallbackAction<_DeleteLastRowIntent>(onInvoke: (_) {
            if (_rows.isNotEmpty) {
              unawaited(_confirmDeleteRow(_rows.length - 1));
            }
            return null;
          }),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }

  Widget _buildIOSScaffold() {
    final cs = Theme.of(context).colorScheme;
    final divider = cs.outlineVariant.withValues(alpha: 0.40);
    final headerBg = cs.surfaceContainerHighest;
    final rowBg = cs.surface;

    final content = Stack(
      children: [
        CustomScrollView(
          slivers: [
            CupertinoSliverNavigationBar(
              largeTitle: Text(_title),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _addHeadersInteractive,
                    child: const Icon(CupertinoIcons.square_grid_2x2),
                  ),
                  const SizedBox(width: 4),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _exportXlsxAndShare,
                    child: const Icon(CupertinoIcons.share_up),
                  ),
                  const SizedBox(width: 4),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _showActionsCupertino,
                    child: const Icon(CupertinoIcons.ellipsis_circle),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(child: _buildTopSummary(divider)),
            SliverToBoxAdapter(child: _buildSegmentedFilters()),
            SliverFillRemaining(
              hasScrollBody: true,
              child: _buildGridArea(divider, headerBg, rowBg),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _frostedBottomBar(
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openFilters,
                  icon: const Icon(CupertinoIcons.line_horizontal_3_decrease),
                  label: const Text('Filtrar / Buscar'),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: OutlinedButton.icon(
                  onPressed: _addHeadersInteractive,
                  icon: const Icon(Icons.view_column),
                  label: const Text('Añadir encabezado'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _exportXlsxAndShare,
                  icon: const Icon(CupertinoIcons.table),
                  label: const Text('Exportar Excel'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: _addRow,
                icon: const Icon(CupertinoIcons.add),
                tooltip: 'Agregar fila',
              ),
            ]),
          ),
        ),
      ],
    );

    return CupertinoPageScaffold(child: _withShortcuts(content));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color divider = cs.outlineVariant.withValues(alpha: 0.40);
    final Color headerBg = cs.surfaceContainerHighest;
    final Color rowBg = cs.surface;

    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    final page = isIOS
        ? _buildIOSScaffold()
        : Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: _buildAppBarMaterial(context),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addHeadersInteractive,
        icon: const Icon(Icons.view_column),
        label: const Text('Añadir encabezado'),
      ),
      bottomNavigationBar: _frostedBottomBar(
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _openFilters,
              icon: const Icon(CupertinoIcons.line_horizontal_3_decrease),
              label: const Text('Filtrar / Buscar'),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: OutlinedButton.icon(
              onPressed: _addHeadersInteractive,
              icon: const Icon(Icons.view_column),
              label: const Text('Añadir encabezado'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: _exportXlsxAndShare,
              icon: const Icon(CupertinoIcons.table),
              label: const Text('Exportar Excel'),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filled(
            onPressed: _addRow,
            icon: const Icon(CupertinoIcons.add),
            tooltip: 'Agregar fila',
          ),
        ]),
      ),
      body: _withShortcuts(
        Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            _buildTopSummary(divider),
            _buildSegmentedFilters(),
            Expanded(child: _buildGridArea(divider, headerBg, rowBg)),
          ],
        ),
      ),
    );

    return Stack(children: [
      Positioned.fill(child: page),
      if (_saving)
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: LinearProgressIndicator(minHeight: 2),
        ),
      if (_isBusy) Positioned.fill(child: _buildBusyOverlay()),
    ]);
  }

  // ----- Crash rehydrate -----
  Future<void> _rehydrateFromCrashGuard() async {
    final s = CrashGuard.I.current();
    if (s.sheetId != _sheetKey) return;

    bool changed = false;

    if (_listCtrl.hasClients && s.scrollOffset > 0) {
      final max = _listCtrl.position.maxScrollExtent;
      final off = s.scrollOffset.clamp(0.0, max);
      _listCtrl.jumpTo(off);
    }

    if (s.draft.isNotEmpty) {
      for (final entry in s.draft.entries) {
        final key = entry.key;
        final parts = key.split(':');
        if (parts.length != 2) continue;
        final row = int.tryParse(parts[0]) ?? -2;
        final colKey = parts[1];
        if (row >= 0 && colKey.startsWith('c')) {
          final col = int.tryParse(colKey.substring(1)) ?? -1;
          if (col >= 0 && row < _rows.length && col < _headers.length) {
            _rows[row].cells[col] = entry.value;
            changed = true;
          }
        } else if (row == -1 && colKey.startsWith('h')) {
          final col = int.tryParse(colKey.substring(1)) ?? -1;
          if (col >= 0 && col < _headers.length) {
            _headers[col] = entry.value;
            changed = true;
          }
        }
      }
      setState(() {});
    }

    if (s.photoPaths.isNotEmpty) {
      final attached = <String>[];
      for (final path in s.photoPaths) {
        if (!io.File(path).existsSync()) continue;
        if (_rows.any((r) => r.photos.contains(path))) continue;

        final idx = _rows.indexWhere((r) => r.photos.length < kMaxPhotosPerRow);
        if (idx == -1 || _totalPhotos() >= kMaxPhotosTotal) break;
        _rows[idx].photos.add(path);
        attached.add(path);
      }
      if (attached.isNotEmpty) {
        setState(() {});
        for (final pth in attached) {
          CrashGuard.I.confirmPhotoLinked(pth);
        }
        _toast('Fotos recuperadas (${attached.length}).');
        changed = true;
      }
    }

    if (changed) _scheduleSave();
  }

  // ----- Gestor de fotos -----
  Future<void> _managePhotos(int rowIndex) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final photos = _rows[rowIndex].photos;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Text('Fotos (${photos.length})',
                    style: Theme.of(ctx).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    unawaited(_addPhotoQuick(rowIndex));
                  },
                  icon: const Icon(Icons.add_a_photo_outlined),
                  tooltip: 'Agregar',
                ),
              ]),
              const SizedBox(height: 8),
              if (photos.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('Sin fotos todavía.'),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: photos.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final path = photos[i];
                      final name = p.basename(path);
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.photo_outlined),
                        title:
                        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => unawaited(OpenFilex.open(path)),
                        trailing: IconButton(
                          tooltip: 'Eliminar',
                          icon:
                          const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () async {
                            setState(() => _rows[rowIndex].photos.removeAt(i));
                            try {
                              await io.File(path).delete();
                            } catch (_) {}
                            _scheduleSave();
                            Navigator.pop(ctx);
                            unawaited(_managePhotos(rowIndex));
                          },
                        ),
                      );
                    },
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }

  // ----- Editor -----
  Future<String?> _showEditor({
    required String title,
    required String initial,
    String placeholder = '',
  }) async {
    final ctrl = TextEditingController(text: initial);
    bool listening = false;
    String livePartial = '';
    double micLevel = 0.0;

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18.0)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSB) {
            final bottom = MediaQuery.of(ctx).viewInsets.bottom;

            Future<void> startDictation() async {
              if (!SpeechService.I.isAvailable) {
                await SpeechService.I.init();
                if (!SpeechService.I.isAvailable) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Dictado no disponible.')));
                  }
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

            void accept() {
              final text = ctrl.text.trim().isEmpty && livePartial.isNotEmpty
                  ? livePartial.trim()
                  : ctrl.text.trim();
              Navigator.pop(ctx, text);
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 10),
                CupertinoTextField(
                  controller: ctrl,
                  autofocus: true,
                  placeholder: placeholder.isEmpty
                      ? (listening && livePartial.isNotEmpty ? '… $livePartial' : '')
                      : placeholder,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  onChanged: (_) {
                    if (livePartial.isNotEmpty) {
                      setSB(() => livePartial = '');
                    }
                  },
                ),
                const SizedBox(height: 8),
                _MicWaveAndGlow(level: micLevel, listening: listening),
                if (listening || livePartial.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      listening
                          ? (livePartial.isEmpty ? '… Escuchando' : '… $livePartial')
                          : (livePartial.isNotEmpty ? 'Sugerencia: $livePartial' : ''),
                      style: Theme.of(ctx)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(ctx).hintColor),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filledTonal(
                    tooltip: listening ? 'Grabando…' : 'Dictar',
                    onPressed: listening ? null : startDictation,
                    icon: Icon(listening ? Icons.mic : Icons.mic_none),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: accept,
                      child: const Text('Guardar'),
                    ),
                  ),
                ]),
              ]),
            );
          },
        );
      },
    );
  }

  Future<void> _editHeader(int col) async {
    final value = await _showEditor(
      title: 'Encabezado',
      initial: _headers[col],
      placeholder: 'ABC',
    );
    if (value == null) return;
    setState(() {
      _headers[col] = value;
      CrashGuard.I.recordCellEdit(rowId: -1, colKey: 'h$col', value: value);
      _recomputeView();
    });
    _scheduleSave();
  }

  Future<void> _editCell(int row, int col) async {
    final value = await _showEditor(
      title: 'Celda (${row + 1}, ${col + 1})',
      initial: _rows[row].cells[col],
    );
    if (value == null) return;
    setState(() {
      _rows[row].cells[col] = value;
      CrashGuard.I.recordCellEdit(rowId: row, colKey: 'c$col', value: value);
      _recomputeView();
    });
    _scheduleSave();
  }

  // ===== Transición fade-through =====
  PageRoute<T> _fadeThroughRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      transitionsBuilder: (_, anim, back, child) {
        final fade = CurvedAnimation(parent: anim, curve: kAppleCurve);
        final scale = Tween<double>(begin: 0.98, end: 1.0)
            .chain(CurveTween(curve: kAppleCurve))
            .animate(anim);
        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
    );
  }

  // ===== HUD suave con miniatura =====
  void _showPhotoHud(String path) {
    _removePhotoHud();

    final overlay = Overlay.of(context);

    final entry = OverlayEntry(
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final imgFile = io.File(path);

        return Positioned(
          left: 12,
          right: 12,
          bottom: 18 + MediaQuery.of(ctx).padding.bottom,
          child: _GlassHud(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    imgFile,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    cacheWidth: 128,
                    cacheHeight: 128,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Foto agregada',
                        style: Theme.of(ctx)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('Guardada en la fila',
                        style:
                        Theme.of(ctx).textTheme.labelSmall?.copyWith(color: cs.outline)),
                  ],
                ),
                const SizedBox(width: 8),
                Icon(Icons.check_circle, size: 20, color: cs.primary),
              ],
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    _photoHud = entry;

    _hudTimer = Timer(kHudDuration, _removePhotoHud);
  }

  void _removePhotoHud() {
    _hudTimer?.cancel();
    _hudTimer = null;
    _photoHud?.remove();
    _photoHud = null;
  }
}

// ===== Intents =====
class _AddRowIntent extends Intent {
  const _AddRowIntent();
}

class _OpenFilterIntent extends Intent {
  const _OpenFilterIntent();
}

class _ExportIntent extends Intent {
  const _ExportIntent();
}

class _DeleteLastRowIntent extends Intent {
  const _DeleteLastRowIntent();
}

// ===== Modelo =====
class _RowModel {
  final int id;
  final List<String> cells;
  final List<String> photos;
  double? lat;
  double? lng;

  _RowModel({required this.id, required this.cells, required this.photos});

  static int _seed = 0;
  factory _RowModel.empty(int cols) => _RowModel(
    id: DateTime.now().microsecondsSinceEpoch + (_seed++),
    cells: List<String>.generate(cols, (_) => ''),
    photos: <String>[],
  );
}

// ===== Widgets =====
class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.width,
    required this.text,
    required this.divider,
    this.onTap,
    this.fill,
    this.isBandStart = false,
  });

  final double width;
  final String text;
  final Color divider;
  final VoidCallback? onTap;
  final Color? fill;
  final bool isBandStart;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );
    return _Cell(
      width: width,
      divider: divider,
      isHeader: true,
      fill: fill,
      isBandStart: isBandStart,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          onLongPress: onTap,
          onDoubleTap: onTap,
          borderRadius: BorderRadius.circular(8.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kCellHPad),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                text.isEmpty ? 'ABC' : text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.width,
    required this.child,
    required this.divider,
    this.isHeader = false,
    this.fill,
    this.isBandStart = false,
  });
  final double width;
  final Widget child;
  final Color divider;
  final bool isHeader;
  final Color? fill;
  final bool isBandStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: isHeader ? kHeaderHeight : kRowHeight,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: fill,
        border: Border(
          left:
          isBandStart ? BorderSide(color: divider, width: 2.0) : BorderSide.none,
          right: BorderSide(color: divider),
          bottom: BorderSide(color: divider),
        ),
      ),
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kCellHPad),
        child: child,
      ),
    );
  }
}

class _CellText extends StatelessWidget {
  const _CellText({required this.text, required this.onTap, this.highlight = ''});
  final String text;
  final String highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final query = highlight.trim().toLowerCase();
    final txt = text.isEmpty ? ' ' : text;
    final idx = query.isEmpty ? -1 : txt.toLowerCase().indexOf(query);

    Widget wrapper(Widget inner) => Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onTap,
        borderRadius: BorderRadius.circular(8.0),
        child: SizedBox.expand(
          child: Align(alignment: Alignment.centerLeft, child: inner),
        ),
      ),
    );

    if (idx < 0) {
      return wrapper(
        Text(
          txt,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    final before = txt.substring(0, idx);
    final match = txt.substring(idx, idx + query.length);
    final after = txt.substring(idx + query.length);

    return wrapper(
      RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(text: before),
            TextSpan(text: match, style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: after),
          ],
        ),
      ),
    );
  }
}

class _CoordPill extends StatelessWidget {
  const _CoordPill({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (ctx, cts) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: cts.maxWidth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Icon(icon, size: 14),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _PhotosButton extends StatelessWidget {
  const _PhotosButton({
    required this.count,
    required this.onTapAdd,
    required this.onTapManage,
    this.busy = false,
  });
  final int count;
  final VoidCallback onTapAdd;
  final VoidCallback onTapManage;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final divider = c.outlineVariant.withValues(alpha: 0.40);

    Widget popBadge(int value) => AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, anim) => ScaleTransition(
        scale: Tween(begin: 0.85, end: 1.0)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: Container(
        key: ValueKey(value),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration:
        BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(10)),
        child: Text('$value',
            style: const TextStyle(
                fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );

    return LayoutBuilder(builder: (ctx, cts) {
      final narrow = cts.maxWidth < 120.0;
      final badge = popBadge(count);

      Widget btn(String label, IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
              border: Border.all(color: divider),
              borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(label),
          ]),
        ),
      );

      if (narrow) {
        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AnimatedSwitcher(
                duration: kMotionFast,
                switchInCurve: kAppleCurve,
                switchOutCurve: kAppleCurve,
                child: busy
                    ? const SizedBox(
                  key: ValueKey('spin-narrow'),
                  width: 18,
                  height: 18,
                  child: Padding(
                    padding: EdgeInsets.all(2),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
                    : InkWell(
                  key: const ValueKey('btn-narrow'),
                  onTap: onTapAdd,
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.add_a_photo_outlined, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed: busy ? null : onTapManage,
                icon: const Icon(Icons.photo_library_outlined, size: 16),
                label: badge,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ]),
          ),
        );
      }

      return Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedSwitcher(
              duration: kMotionFast,
              switchInCurve: kAppleCurve,
              switchOutCurve: kAppleCurve,
              child: busy
                  ? Container(
                key: const ValueKey('spin-wide'),
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: divider),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
                  : btn('Agregar', Icons.add_a_photo_outlined, onTapAdd),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: busy ? null : onTapManage,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    border: Border.all(color: divider),
                    borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.photo_library_outlined, size: 18),
                  const SizedBox(width: 6),
                  badge,
                ]),
              ),
            ),
          ]),
        ),
      );
    });
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

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
      curve: kAppleCurve,
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
              curve: kAppleCurve,
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

// ===== Glass HUD =====
class _GlassHud extends StatefulWidget {
  const _GlassHud({required this.child});
  final Widget child;

  @override
  State<_GlassHud> createState() => _GlassHudState();
}

class _GlassHudState extends State<_GlassHud> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  late final Animation<double> _fade =
  CurvedAnimation(parent: _c, curve: kAppleCurve);
  late final Animation<Offset> _slide =
  Tween(begin: const Offset(0, 0.1), end: Offset.zero)
      .chain(CurveTween(curve: kAppleCurve))
      .animate(_c);

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: widget.child,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(position: _slide, child: card),
        ),
      ),
    );
  }
}
