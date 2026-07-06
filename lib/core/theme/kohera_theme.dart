import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:kohera/core/theme/kohera_palette.dart';
import 'package:kohera/core/theme/theme_presets.dart';

class KoheraTheme {
  KoheraTheme._();

  static const Color _fallbackSeed = Color(0xFF1976D2);

  // ── Light ──────────────────────────────────────────────────────
  static ThemeData light(
      {ColorScheme? dynamic, ThemePreset? preset, KoheraPalette? palette,}) {
    final colorScheme = preset?.light() ??
        dynamic ??
        ColorScheme.fromSeed(seedColor: _fallbackSeed);
    return _build(colorScheme, Brightness.light, preset, palette);
  }

  // ── Dark ───────────────────────────────────────────────────────
  static ThemeData dark(
      {ColorScheme? dynamic, ThemePreset? preset, KoheraPalette? palette,}) {
    final colorScheme = preset?.dark() ??
        dynamic ??
        ColorScheme.fromSeed(
            seedColor: _fallbackSeed, brightness: Brightness.dark,);
    return _build(colorScheme, Brightness.dark, preset, palette);
  }

  // ── Shared builder ─────────────────────────────────────────────
  static ThemeData _build(ColorScheme cs, Brightness brightness,
      [ThemePreset? preset, KoheraPalette? palette,]) {
    final isLight = brightness == Brightness.light;

    // Explicit palette (custom themes) → preset palette → derive from scheme.
    final resolvedPalette = palette ??
        preset?.pixel(brightness) ??
        KoheraPalette.fromColorScheme(cs, brightness);

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      brightness: brightness,
      scaffoldBackgroundColor: cs.surface,
      extensions: [resolvedPalette],

      // Typography
      textTheme: _textTheme(cs),

      // App bar
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
          letterSpacing: 0, // Remove negative letter spacing for pixel fonts
        ),
      ),

      // Navigation rail (the space icon rail)
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isLight ? cs.surfaceContainerLow : cs.surfaceContainerHigh,
        indicatorColor: cs.primaryContainer,
        selectedIconTheme: IconThemeData(color: cs.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: cs.onSurfaceVariant),
        labelType: NavigationRailLabelType.none,
      ),

      // Navigation bar (bottom bar on mobile)
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: cs.surface,
        indicatorColor: cs.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),

      // Cards
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)), // Sharp corners
        color: isLight ? cs.surfaceContainerLowest : cs.surfaceContainer,
      ),

      // Dialogs, sheets & menus — sharp corners for pixel theme
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(),
      ),
      menuTheme: const MenuThemeData(
        style: MenuStyle(
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(),
          ),
        ),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        menuStyle: MenuStyle(
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(),
          ),
        ),
      ),

      // Input decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(0), // Sharp corners
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),

      // Floating action button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)), // Sharp corners
      ),

      // List tiles — explicit click cursor for desktop platforms
      listTileTheme: const ListTileThemeData(
        mouseCursor: WidgetStateMouseCursor.clickable,
      ),

      // Popup menus — explicit click cursor for desktop platforms
      popupMenuTheme: const PopupMenuThemeData(
        mouseCursor: WidgetStateMouseCursor.clickable,
        shape: RoundedRectangleBorder(),
      ),

      // Buttons — explicit click cursor for desktop platforms
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all<RoundedRectangleBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)), // Sharp corners
          ),
          mouseCursor: WidgetStateMouseCursor.clickable,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all<RoundedRectangleBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)), // Sharp corners
          ),
          mouseCursor: WidgetStateMouseCursor.clickable,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all<RoundedRectangleBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)), // Sharp corners
          ),
          mouseCursor: WidgetStateMouseCursor.clickable,
        ),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(
          mouseCursor: WidgetStateMouseCursor.clickable,
        ),
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: cs.outlineVariant.withValues(alpha: 0.4),
        thickness: 1,
        space: 1,
      ),

      // Page transitions
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  // ── Text theme ─────────────────────────────────────────────────
  static TextTheme _textTheme(ColorScheme cs) {
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'PressStart2P',
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: 0, // Remove negative letter spacing for pixel fonts
        color: cs.onSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'PressStart2P',
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: 0, // Remove negative letter spacing for pixel fonts
        color: cs.onSurface,
      ),
      titleLarge: TextStyle(
        fontFamily: 'PressStart2P',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: 0, // Remove negative letter spacing for pixel fonts
        color: cs.onSurface,
      ),
      titleMedium: TextStyle(
        fontFamily: 'DepartureMono',
        fontSize: 15,
        fontWeight: FontWeight.w500,
        letterSpacing: 0, // Remove negative letter spacing for pixel fonts
        color: cs.onSurface,
      ),
      bodyLarge: TextStyle(
        fontFamily: 'DepartureMono',
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: cs.onSurface,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'DepartureMono',
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: cs.onSurfaceVariant,
      ),
      labelSmall: TextStyle(
        fontFamily: 'DepartureMono',
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0, // Remove negative letter spacing for pixel fonts
        color: cs.onSurfaceVariant,
      ),
    );
  }
}
