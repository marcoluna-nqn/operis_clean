// lib/main.dart
import 'dart:async';
import 'dart:isolate';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/crash_guard.dart';
import 'services/notify_service.dart';
import 'services/net.dart';
import 'services/pending_share_store.dart';

import 'screens/home_screen.dart';
import 'screens/beta_sheet_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/export_center_screen.dart';

// Licensing
import 'licensing/license_manager.dart';
import 'licensing/license_gate.dart';

// Fotos por fila
// ===== Canal nativo para guardar PNG en MediaStore (Android) =====
const MethodChannel _mediaCh = MethodChannel('com.gridnote.bitacora/media');

Future<String?> savePngToPictures(String name, Uint8List bytes) async {
  if (!Platform.isAndroid) return null;
  try {
    return await _mediaCh.invokeMethod<String>('saveImage', {
      'name': name,
      'bytes': bytes,
    });
  } catch (e) {
    debugPrint('saveImage error: $e');
    return null;
  }
}

// Utilidad de prueba en debug: genera un PNG simple
Future<Uint8List> _makeTestPng(int w, int h) async {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const Color(0xFF0A84FF),
  );
  final img = await rec.endRecording().toImage(w, h);
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  return bd!.buffer.asUint8List();
}

// =================================================================

class GNScrollBehavior extends MaterialScrollBehavior {
  const GNScrollBehavior({this.alwaysBounce = true});
  final bool alwaysBounce;
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      alwaysBounce ? const BouncingScrollPhysics() : super.getScrollPhysics(context);
}

class _ResumeObserver extends StatefulWidget {
  const _ResumeObserver({required this.child});
  final Widget child;
  @override
  State<_ResumeObserver> createState() => _ResumeObserverState();
}

class _ResumeObserverState extends State<_ResumeObserver> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(PendingShareStore.I.processQueueIfOnline());
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(CrashGuard.I.flushNow());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> _postBoot() async {
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
      statusBarColor: Color(0x00000000),
    ));
  }
  unawaited(NotifyService.I.init().catchError((_) {}));
  unawaited(PendingShareStore.I.processQueueIfOnline());

  // Prueba automÃ¡tica solo en debug: correr tras el primer frame
  if (kDebugMode && Platform.isAndroid) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final bytes = await _makeTestPng(400, 200);
      final u1 = await savePngToPictures('battery_scale.png', bytes);
      final u2 = await savePngToPictures('battery_fail.png', bytes);
      debugPrint('saved URIs: $u1 | $u2');
    });
  }
}

void _hookCrashFlush() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    unawaited(CrashGuard.I.flushNow());
  };
  ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    unawaited(CrashGuard.I.flushNow());
    return true;
  };
  Isolate.current.addErrorListener(
    RawReceivePort((dynamic _) async {
      await CrashGuard.I.flushNow();
    }).sendPort,
  );
}

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
        await Firebase.initializeApp();
      }
    } catch (_) {}

    await Net.I.init();
    await PendingShareStore.I.init();

    await CrashGuard.I.init()
        .timeout(const Duration(milliseconds: 1200))
        .catchError((_) {});
    _hookCrashFlush();

    await LicenseManager.instance.init();

    final prefs = await SharedPreferences.getInstance();
    final showOnboarding = !(prefs.getBool('onboarding_seen') ?? false);

    runApp(ProviderScope(child: _RootApp(showOnboarding: showOnboarding)));
    unawaited(_postBoot());
  }, (Object e, StackTrace st) {
    unawaited(CrashGuard.I.flushNow());
  });
}

class _RootApp extends StatelessWidget {
  const _RootApp({required this.showOnboarding});
  final bool showOnboarding;

  static const baseSeed = Color(0xFF0A84FF);
  static final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    Widget gate(Widget child) => LicenseGate(
      showBannerWhenActive: true,
      navigatorKey: _navKey,
      child: child,
    );

    switch (settings.name) {
      case '/':
        return _fade(gate(const HomeScreen()), settings);
      case '/sheet':
        {
          final pid = (settings.arguments as String?) ?? 'PLANILLA_123';
          return _cupertino(gate(const BetaSheetScreen()), settings);
        }
      case '/settings':
        return _cupertino(gate(const SettingsScreen()), settings);
      case '/export':
        return _cupertino(gate(const ExportCenterScreen()), settings);
      case '/onboarding':
        return _cupertino(const _OnboardingScreen(), settings);
      case '/photos':
        {
          final a = (settings.arguments as Map?) ?? const {};
          final pid = a['planillaId'] as String? ?? 'dev';
          final rid = a['rowId'] as String? ?? 'fila1';
          return _cupertino(gate(const BetaSheetScreen()), settings);
        }
      default:
        return _cupertino(gate(const HomeScreen()), const RouteSettings(name: '/'));
    }
  }

  static PageRoute<void> _cupertino(Widget child, RouteSettings settings) =>
      CupertinoPageRoute<void>(builder: (_) => child, settings: settings);

  static PageRoute<void> _fade(Widget child, RouteSettings settings) =>
      PageRouteBuilder<void>(
        settings: settings,
        pageBuilder: (_, __, ___) => child,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      );

  @override
  Widget build(BuildContext context) {
    // Forzar Exportar como ruta inicial para probar
    final String initial = '/export';

    final light = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: baseSeed,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF7F8FA),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
      }),
    );

    final dark = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: baseSeed, brightness: Brightness.dark),
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: const AppBarTheme(backgroundColor: Colors.black),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
      }),
    );

    ErrorWidget.builder = (FlutterErrorDetails details) {
      const isRelease = bool.fromEnvironment('dart.vm.product');
      if (!isRelease) return ErrorWidget(details.exception);
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, size: 36),
              SizedBox(height: 12),
              Text('OcurriÃ³ un problema. Estamos trabajando en ello.'),
            ],
          ),
        ),
      );
    };

    return _ResumeObserver(
      child: MaterialApp(
        navigatorKey: _navKey,
        debugShowCheckedModeBanner: false,
        title: 'BitÃ¡cora',
        restorationScopeId: 'root',
        themeMode: ThemeMode.light, // forzado claro
        theme: light,
        darkTheme: dark,
        scrollBehavior: const GNScrollBehavior(alwaysBounce: true),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('es', 'AR'), Locale('es'), Locale('en')],
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          final clamped = mq.textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.30);
          return MediaQuery(
            data: mq.copyWith(textScaler: clamped),
            child: child ?? const SizedBox.shrink(),
          );
        },
        onGenerateRoute: _onGenerateRoute,
        initialRoute: initial,
      ),
    );
  }
}

class _OnboardingScreen extends StatefulWidget {
  const _OnboardingScreen();
  @override
  State<_OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<_OnboardingScreen> {
  final _ctrl = PageController();
  int _page = 0;

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/');
  }

  void _next() {
    if (_page >= 3) {
      _finish();
    } else {
      _ctrl.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: _finish, child: const Text('Saltar')),
          ),
          Expanded(
            child: PageView(
              controller: _ctrl,
              onPageChanged: (i) => setState(() => _page = i),
              children: const [
                _OnbPage(
                  icon: Icons.table_view_outlined,
                  title: 'Planillas rÃ¡pidas',
                  body:
                  'EmpezÃ¡ una bitÃ¡cora en segundos. EditÃ¡ tÃ­tulos y celdas con un toque. Todo se guarda solo.',
                ),
                _OnbPage(
                  icon: Icons.photo_camera_back_outlined,
                  title: 'Fotos + GPS',
                  body:
                  'SacÃ¡ fotos por fila y marcÃ¡ ubicaciÃ³n precisa, incluso sin seÃ±al. Todo queda en la misma planilla.',
                ),
                _OnbPage(
                  icon: Icons.ios_share,
                  title: 'Excel a prueba de balas',
                  body:
                  'ExportÃ¡ un XLSX compatible (con miniaturas y filtros) y una vista previa PNG para ver en el correo.',
                ),
                _OnbPage(
                  icon: Icons.rocket_launch_outlined,
                  title: 'Listo para trabajar',
                  body:
                  'Funciona offline, es rÃ¡pido y simple. Desde NeuquÃ©n al mundo. Â¡Vamos!',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _Dots(total: 4, index: _page),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _next,
                icon: Icon(_page < 3 ? Icons.arrow_forward : Icons.check),
                label: Text(_page < 3 ? 'Siguiente' : 'Empezar'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _OnbPage extends StatelessWidget {
  const _OnbPage({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Column(children: [
        const SizedBox(height: 6),
        Icon(icon, size: 88, color: cs.primary),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(
          body,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
        ),
      ]),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.total, required this.index});
  final int total;
  final int index;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? cs.primary : cs.outlineVariant,
            borderRadius: BorderRadius.circular(8),
          ),
        );
      }),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const _RootApp(showOnboarding: false);
}

