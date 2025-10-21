// lib/constants/colors.dart
import 'package:flutter/material.dart';

/// Paleta + temas Material 3 de Gridnote (limpio y moderno)
class AppColors {
  AppColors._();

  // Semilla de marca (cian Gridnote)
  static const seed = Color(0xFF00BCD4);
  static const primary = seed;
  static const white = Colors.white;
  static const black = Colors.black;

  // Swatch legacy por compatibilidad
  static const MaterialColor primarySwatch = MaterialColor(0xFF00BCD4, {
    50: Color(0xFFE0F7FA),
    100: Color(0xFFB2EBF2),
    200: Color(0xFF80DEEA),
    300: Color(0xFF4DD0E1),
    400: Color(0xFF26C6DA),
    500: Color(0xFF00BCD4),
    600: Color(0xFF00ACC1),
    700: Color(0xFF0097A7),
    800: Color(0xFF00838F),
    900: Color(0xFF006064),
  });

  // Esquemas derivados de la semilla
  static final ColorScheme lightScheme =
  ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);

  static final ColorScheme darkScheme =
  ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);

  // Temas listos
  static ThemeData lightTheme() => _buildTheme(lightScheme);
  static ThemeData darkTheme() => _buildTheme(darkScheme);

  static ThemeData _buildTheme(ColorScheme s) {
    final brand = AppBrand.fromScheme(s);
    final r12 = BorderRadius.circular(12);
    final r14 = BorderRadius.circular(14);
    final r16 = BorderRadius.circular(16);
    final r20 = BorderRadius.circular(20);

    return ThemeData(
      useMaterial3: true,
      colorScheme: s,
      scaffoldBackgroundColor: s.surface,
      splashFactory: InkSparkle.splashFactory,

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: s.surface,
        foregroundColor: s.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: s.onSurface,
          fontWeight: FontWeight.w700,
          fontSize: 18,
          letterSpacing: .1,
        ),
      ),

      // Tarjetas
      cardTheme: CardThemeData(
        color: s.surface,
        surfaceTintColor: s.primary,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: brand.radius),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),

      // Botones
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: r14),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: r14),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: r14),
          side: BorderSide(color: s.outline),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: r12),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),

      // Inputs
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: s.surfaceContainerHighest,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        hintStyle: TextStyle(color: s.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: r12,
          borderSide: BorderSide(color: s.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: r12,
          borderSide: BorderSide(color: s.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: r12,
          borderSide: BorderSide(color: s.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: r12,
          borderSide: BorderSide(color: s.error, width: 2),
        ),
      ),

      // Chips
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: s.outlineVariant),
        selectedColor: s.secondaryContainer,
        disabledColor: s.surfaceContainerHighest,
        labelStyle: TextStyle(color: s.onSurface),
        secondaryLabelStyle: TextStyle(color: s.onSecondaryContainer),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      // Diálogos y bottom sheets
      dialogTheme: DialogThemeData(
        backgroundColor: s.surface,
        surfaceTintColor: s.primary,
        shape: RoundedRectangleBorder(borderRadius: r20),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: s.surface,
        surfaceTintColor: s.primary,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: r20.topLeft),
        ),
      ),

      // Navegación inferior
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: s.surface,
        indicatorColor: s.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      // Tabs
      tabBarTheme: TabBarThemeData(
        labelColor: s.primary,
        unselectedLabelColor: s.onSurfaceVariant,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: s.primary, width: 2),
          insets: const EdgeInsets.symmetric(horizontal: 16),
        ),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),

      // ListTiles y divisores
      listTileTheme: ListTileThemeData(
        iconColor: s.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: r16),
      ),
      dividerTheme: DividerThemeData(
        color: s.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      // Snackbars
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: s.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: s.onSurface),
        actionTextColor: s.primary,
        shape: RoundedRectangleBorder(borderRadius: r14),
      ),

      // FAB e iconos
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        foregroundColor: s.onPrimaryContainer,
        backgroundColor: s.primaryContainer,
        shape: RoundedRectangleBorder(borderRadius: r16),
        elevation: 4,
      ),
      iconTheme: IconThemeData(color: s.onSurfaceVariant),

      // Tipografía
      textTheme: _textThemeTweaks(s),

      // Extensiones de marca
      extensions: <ThemeExtension<dynamic>>[brand],
    );
  }

  static TextTheme _textThemeTweaks(ColorScheme s) {
    const w600 = FontWeight.w600;
    const w700 = FontWeight.w700;
    return Typography.material2021(platform: TargetPlatform.android)
        .black
        .merge(Typography.material2021(platform: TargetPlatform.android).white)
        .apply(displayColor: s.onSurface, bodyColor: s.onSurface)
        .copyWith(
      titleLarge: const TextStyle(fontWeight: w700),
      titleMedium: const TextStyle(fontWeight: w700),
      titleSmall: const TextStyle(fontWeight: w700),
      bodyLarge: const TextStyle(fontWeight: w600),
      bodyMedium: const TextStyle(fontWeight: w600),
      labelLarge: const TextStyle(fontWeight: w700, letterSpacing: .2),
      labelMedium: const TextStyle(fontWeight: w700, letterSpacing: .1),
    );
  }
}

/// Extensión de marca: gradiente y radios coherentes
@immutable
class AppBrand extends ThemeExtension<AppBrand> {
  final Gradient headerGradient;
  final BorderRadiusGeometry radius;
  final List<BoxShadow> softShadow;

  const AppBrand({
    required this.headerGradient,
    required this.radius,
    required this.softShadow,
  });

  factory AppBrand.fromScheme(ColorScheme s) {
    return AppBrand(
      headerGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [s.primary, s.secondary],
      ),
      radius: BorderRadius.circular(16),
      softShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24),
      ],
    );
  }

  @override
  AppBrand copyWith({
    Gradient? headerGradient,
    BorderRadiusGeometry? radius,
    List<BoxShadow>? softShadow,
  }) {
    return AppBrand(
      headerGradient: headerGradient ?? this.headerGradient,
      radius: radius ?? this.radius,
      softShadow: softShadow ?? this.softShadow,
    );
  }

  @override
  AppBrand lerp(ThemeExtension<AppBrand>? other, double t) {
    if (other is! AppBrand) return this;
    return t < .5 ? this : other;
  }
}
