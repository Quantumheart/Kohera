import 'package:flutter/material.dart';
import 'package:kohera/core/theme/kohera_palette.dart';

class ThemePreset {
  const ThemePreset({
    required this.id,
    required this.name,
    required this.seedColor,
    this.forcedMode,
    this.lightScheme,
    this.darkScheme,
    this.pixelPalette,
  });

  final String id;
  final String name;
  final Color seedColor;
  final ThemeMode? forcedMode;
  final ColorScheme? lightScheme;
  final ColorScheme? darkScheme;

  /// Factory that produces the [KoheraPalette] for this preset.
  /// If null, the theme builder defaults to PICO-8.
  final KoheraPalette Function(Brightness)? pixelPalette;

  ColorScheme light() =>
      lightScheme ?? ColorScheme.fromSeed(seedColor: seedColor);

  ColorScheme dark() =>
      darkScheme ??
      ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark);

  /// Resolve the pixel palette for a given brightness, or null when this
  /// preset defines none (the builder then derives one from the ColorScheme).
  KoheraPalette? pixel(Brightness b) => pixelPalette?.call(b);
}

const _presets = <ThemePreset>[
  // ── Core themes ──────────────────────────────────────────────
  ThemePreset(
    id: 'black',
    name: 'Black',
    seedColor: Color(0xFF000000),
    forcedMode: ThemeMode.dark,
    lightScheme: ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF424242),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFE0E0E0),
      onPrimaryContainer: Color(0xFF212121),
      secondary: Color(0xFF616161),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFEEEEEE),
      onSecondaryContainer: Color(0xFF424242),
      tertiary: Color(0xFF757575),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFF5F5F5),
      onTertiaryContainer: Color(0xFF424242),
      error: Color(0xFFB3261E),
      onError: Color(0xFFFFFFFF),
      surface: Color(0xFFFAFAFA),
      onSurface: Color(0xFF1B1B1B),
      onSurfaceVariant: Color(0xFF616161),
      outline: Color(0xFF9E9E9E),
      outlineVariant: Color(0xFFE0E0E0),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF5F5F5),
      surfaceContainer: Color(0xFFF0F0F0),
      surfaceContainerHigh: Color(0xFFEBEBEB),
      surfaceContainerHighest: Color(0xFFE0E0E0),
    ),
    darkScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFBDBDBD),
      onPrimary: Color(0xFF000000),
      primaryContainer: Color(0xFF424242),
      onPrimaryContainer: Color(0xFFE0E0E0),
      secondary: Color(0xFF9E9E9E),
      onSecondary: Color(0xFF000000),
      secondaryContainer: Color(0xFF333333),
      onSecondaryContainer: Color(0xFFBDBDBD),
      tertiary: Color(0xFF757575),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFF2C2C2C),
      onTertiaryContainer: Color(0xFF9E9E9E),
      error: Color(0xFFF2B8B5),
      onError: Color(0xFF601410),
      surface: Color(0xFF121212),
      onSurface: Color(0xFFE0E0E0),
      onSurfaceVariant: Color(0xFF9E9E9E),
      outline: Color(0xFF616161),
      outlineVariant: Color(0xFF333333),
      surfaceContainerLowest: Color(0xFF0A0A0A),
      surfaceContainerLow: Color(0xFF1A1A1A),
      surfaceContainer: Color(0xFF1E1E1E),
      surfaceContainerHigh: Color(0xFF252525),
      surfaceContainerHighest: Color(0xFF2C2C2C),
    ),
  ),
  ThemePreset(
    id: 'white',
    name: 'White',
    seedColor: Color(0xFFBDBDBD),
    forcedMode: ThemeMode.light,
    lightScheme: ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF5C6670),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFDDE3EA),
      onPrimaryContainer: Color(0xFF3A4249),
      secondary: Color(0xFF6B7680),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFE8ECF0),
      onSecondaryContainer: Color(0xFF4A535B),
      tertiary: Color(0xFF7D8690),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFF0F2F5),
      onTertiaryContainer: Color(0xFF5C6670),
      error: Color(0xFFB3261E),
      onError: Color(0xFFFFFFFF),
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF1A1C1E),
      onSurfaceVariant: Color(0xFF6B7680),
      outline: Color(0xFFAEB5BD),
      outlineVariant: Color(0xFFDDE3EA),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF8F9FA),
      surfaceContainer: Color(0xFFF2F4F5),
      surfaceContainerHigh: Color(0xFFECEEF0),
      surfaceContainerHighest: Color(0xFFE8EAEC),
    ),
    darkScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFBEC6D0),
      onPrimary: Color(0xFF2A3139),
      primaryContainer: Color(0xFF404850),
      onPrimaryContainer: Color(0xFFDDE3EA),
      secondary: Color(0xFFADB7C1),
      onSecondary: Color(0xFF333B43),
      secondaryContainer: Color(0xFF4A535B),
      onSecondaryContainer: Color(0xFFCDD5DD),
      tertiary: Color(0xFF9DA7B1),
      onTertiary: Color(0xFF3E464E),
      tertiaryContainer: Color(0xFF545C64),
      onTertiaryContainer: Color(0xFFBEC6D0),
      error: Color(0xFFF2B8B5),
      onError: Color(0xFF601410),
      surface: Color(0xFF1A1C1E),
      onSurface: Color(0xFFE2E4E6),
      onSurfaceVariant: Color(0xFF9DA7B1),
      outline: Color(0xFF6B7680),
      outlineVariant: Color(0xFF333B43),
      surfaceContainerLowest: Color(0xFF111315),
      surfaceContainerLow: Color(0xFF1E2023),
      surfaceContainer: Color(0xFF232628),
      surfaceContainerHigh: Color(0xFF2A2D30),
      surfaceContainerHighest: Color(0xFF333538),
    ),
  ),
  ThemePreset(
    id: 'dark',
    name: 'Dark',
    seedColor: Color(0xFF546E7A),
    forcedMode: ThemeMode.dark,
    darkScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF90A4AE),
      onPrimary: Color(0xFF1A2327),
      primaryContainer: Color(0xFF37474F),
      onPrimaryContainer: Color(0xFFB0BEC5),
      secondary: Color(0xFF80CBC4),
      onSecondary: Color(0xFF1A2327),
      secondaryContainer: Color(0xFF2C4A47),
      onSecondaryContainer: Color(0xFFA8DDD8),
      tertiary: Color(0xFFA5D6A7),
      onTertiary: Color(0xFF1A2327),
      tertiaryContainer: Color(0xFF2E4A30),
      onTertiaryContainer: Color(0xFFC8E6C9),
      error: Color(0xFFEF9A9A),
      onError: Color(0xFF3B1010),
      surface: Color(0xFF1C2529),
      onSurface: Color(0xFFE0E4E7),
      onSurfaceVariant: Color(0xFF8E9EA6),
      outline: Color(0xFF5C6E76),
      outlineVariant: Color(0xFF344046),
      surfaceContainerLowest: Color(0xFF141B1E),
      surfaceContainerLow: Color(0xFF1C2529),
      surfaceContainer: Color(0xFF212C31),
      surfaceContainerHigh: Color(0xFF283438),
      surfaceContainerHighest: Color(0xFF303D42),
    ),
  ),

  // ── Color themes ─────────────────────────────────────────────
  ThemePreset(
    id: 'ocean',
    name: 'Ocean',
    seedColor: Color(0xFF006D77),
  ),
  ThemePreset(
    id: 'purple',
    name: 'Purple',
    seedColor: Color(0xFF6750A4),
  ),
  ThemePreset(
    id: 'forest',
    name: 'Forest',
    seedColor: Color(0xFF2E7D32),
  ),

  // ── Catppuccin-inspired themes ───────────────────────────────
  ThemePreset(
    id: 'mocha',
    name: 'Mocha',
    seedColor: Color(0xFFCBA6F7),
    forcedMode: ThemeMode.dark,
    darkScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFCBA6F7),
      onPrimary: Color(0xFF1E1E2E),
      primaryContainer: Color(0xFF45275A),
      onPrimaryContainer: Color(0xFFE8D5FF),
      secondary: Color(0xFFF5C2E7),
      onSecondary: Color(0xFF1E1E2E),
      secondaryContainer: Color(0xFF5A3050),
      onSecondaryContainer: Color(0xFFF5D5EE),
      tertiary: Color(0xFFF38BA8),
      onTertiary: Color(0xFF1E1E2E),
      tertiaryContainer: Color(0xFF5A2535),
      onTertiaryContainer: Color(0xFFF5C5D0),
      error: Color(0xFFF38BA8),
      onError: Color(0xFF1E1E2E),
      surface: Color(0xFF1E1E2E),
      onSurface: Color(0xFFCDD6F4),
      onSurfaceVariant: Color(0xFFA6ADC8),
      outline: Color(0xFF6C7086),
      outlineVariant: Color(0xFF45475A),
      surfaceContainerLowest: Color(0xFF11111B),
      surfaceContainerLow: Color(0xFF181825),
      surfaceContainer: Color(0xFF1E1E2E),
      surfaceContainerHigh: Color(0xFF262637),
      surfaceContainerHighest: Color(0xFF313244),
    ),
  ),
  ThemePreset(
    id: 'macchiato',
    name: 'Macchiato',
    seedColor: Color(0xFFC6A0F6),
    forcedMode: ThemeMode.dark,
    darkScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFC6A0F6),
      onPrimary: Color(0xFF24273A),
      primaryContainer: Color(0xFF42255A),
      onPrimaryContainer: Color(0xFFE4D0FF),
      secondary: Color(0xFFF0C6C6),
      onSecondary: Color(0xFF24273A),
      secondaryContainer: Color(0xFF5A3040),
      onSecondaryContainer: Color(0xFFF5D8D8),
      tertiary: Color(0xFFED8796),
      onTertiary: Color(0xFF24273A),
      tertiaryContainer: Color(0xFF582530),
      onTertiaryContainer: Color(0xFFF5C0C8),
      error: Color(0xFFED8796),
      onError: Color(0xFF24273A),
      surface: Color(0xFF24273A),
      onSurface: Color(0xFFCAD3F5),
      onSurfaceVariant: Color(0xFFA5ADCB),
      outline: Color(0xFF6E738D),
      outlineVariant: Color(0xFF494D64),
      surfaceContainerLowest: Color(0xFF181926),
      surfaceContainerLow: Color(0xFF1E2030),
      surfaceContainer: Color(0xFF24273A),
      surfaceContainerHigh: Color(0xFF2C2F44),
      surfaceContainerHighest: Color(0xFF363A4F),
    ),
  ),
  ThemePreset(
    id: 'frappe',
    name: 'Frappé',
    seedColor: Color(0xFFBBBBF6),
    forcedMode: ThemeMode.dark,
    darkScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFBBBBF6),
      onPrimary: Color(0xFF303446),
      primaryContainer: Color(0xFF3E3F6E),
      onPrimaryContainer: Color(0xFFD8D8FF),
      secondary: Color(0xFFF2D5CF),
      onSecondary: Color(0xFF303446),
      secondaryContainer: Color(0xFF5A4040),
      onSecondaryContainer: Color(0xFFF5E0DA),
      tertiary: Color(0xFFE78284),
      onTertiary: Color(0xFF303446),
      tertiaryContainer: Color(0xFF552528),
      onTertiaryContainer: Color(0xFFF5B8BA),
      error: Color(0xFFE78284),
      onError: Color(0xFF303446),
      surface: Color(0xFF303446),
      onSurface: Color(0xFFC6D0F5),
      onSurfaceVariant: Color(0xFFA5ADCE),
      outline: Color(0xFF737994),
      outlineVariant: Color(0xFF51576D),
      surfaceContainerLowest: Color(0xFF232634),
      surfaceContainerLow: Color(0xFF292C3C),
      surfaceContainer: Color(0xFF303446),
      surfaceContainerHigh: Color(0xFF383C50),
      surfaceContainerHighest: Color(0xFF414559),
    ),
  ),
  ThemePreset(
    id: 'latte',
    name: 'Latte',
    seedColor: Color(0xFF8839EF),
    forcedMode: ThemeMode.light,
    lightScheme: ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF8839EF),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFECDDFF),
      onPrimaryContainer: Color(0xFF5C2D91),
      secondary: Color(0xFF179299),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFB5ECEF),
      onSecondaryContainer: Color(0xFF0E6166),
      tertiary: Color(0xFFDF8E1D),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFFFE0A0),
      onTertiaryContainer: Color(0xFF7A4E10),
      error: Color(0xFFD20F39),
      onError: Color(0xFFFFFFFF),
      surface: Color(0xFFEFF1F5),
      onSurface: Color(0xFF4C4F69),
      onSurfaceVariant: Color(0xFF6C6F85),
      outline: Color(0xFF9CA0B0),
      outlineVariant: Color(0xFFCCD0DA),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFE6E9EF),
      surfaceContainer: Color(0xFFDCE0E8),
      surfaceContainerHigh: Color(0xFFD4D7E0),
      surfaceContainerHighest: Color(0xFFCCD0DA),
    ),
  ),

  // ── Pixel themes ─────────────────────────────────────────────
  ThemePreset(
    id: 'pico8',
    name: 'PICO-8',
    seedColor: Color(0xFF008751),
    pixelPalette: KoheraPalette.pico8,
    // PICO-8 palette (https://www.lexaloffle.com/pico-8.php)
    // 0:black 1:dark-blue 2:dark-purple 3:dark-green 4:brown
    // 5:dark-gray 6:light-gray 7:white 8:red 9:orange
    // 10:yellow 11:green 12:blue 13:lavender 14:pink 15:light-peach
    darkScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF29ADFF),       // PICO-8 blue
      onPrimary: Color(0xFF000000),     // black
      primaryContainer: Color(0xFF1D2B53), // dark-blue
      onPrimaryContainer: Color(0xFFFFF1E8), // white
      secondary: Color(0xFF83769C),      // PICO-8 lavender
      onSecondary: Color(0xFF000000),   // black
      secondaryContainer: Color(0xFF7E2553), // dark-purple
      onSecondaryContainer: Color(0xFFFFF1E8), // white
      tertiary: Color(0xFFFFEC27),       // PICO-8 yellow
      onTertiary: Color(0xFF000000),    // black
      tertiaryContainer: Color(0xFFAB5236), // brown
      onTertiaryContainer: Color(0xFFFFF1E8), // white
      error: Color(0xFFFF004D),          // PICO-8 red
      onError: Color(0xFFFFF1E8),       // white
      surface: Color(0xFF000000),        // black
      onSurface: Color(0xFFFFF1E8),     // white
      onSurfaceVariant: Color(0xFFC2C3C7), // light-gray
      outline: Color(0xFF5F574F),       // dark-gray
      outlineVariant: Color(0xFF5F574F), // dark-gray
      surfaceContainerLowest: Color(0xFF000000),  // black
      surfaceContainerLow: Color(0xFF1D2B53),    // dark-blue
      surfaceContainer: Color(0xFF1D2B53),      // dark-blue
      surfaceContainerHigh: Color(0xFF5F574F),   // dark-gray
      surfaceContainerHighest: Color(0xFF5F574F), // dark-gray
    ),
    lightScheme: ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF008751),       // PICO-8 dark-green
      onPrimary: Color(0xFFFFF1E8),     // white
      primaryContainer: Color(0xFF00E436), // PICO-8 green
      onPrimaryContainer: Color(0xFF000000), // black
      secondary: Color(0xFFAB5236),      // PICO-8 brown
      onSecondary: Color(0xFFFFF1E8),   // white
      secondaryContainer: Color(0xFFFFCCAA), // light-peach
      onSecondaryContainer: Color(0xFF000000), // black
      tertiary: Color(0xFFFFA300),       // PICO-8 orange
      onTertiary: Color(0xFF000000),    // black
      tertiaryContainer: Color(0xFFFFEC27), // yellow
      onTertiaryContainer: Color(0xFF000000), // black
      error: Color(0xFFFF004D),          // PICO-8 red
      onError: Color(0xFFFFF1E8),       // white
      surface: Color(0xFFFFF1E8),        // PICO-8 white
      onSurface: Color(0xFF000000),     // black
      onSurfaceVariant: Color(0xFF5F574F), // dark-gray
      outline: Color(0xFF5F574F),       // dark-gray
      outlineVariant: Color(0xFFC2C3C7), // light-gray
      surfaceContainerLowest: Color(0xFFFFF1E8),  // white
      surfaceContainerLow: Color(0xFFFFCCAA),    // light-peach
      surfaceContainer: Color(0xFFC2C3C7),      // light-gray
      surfaceContainerHigh: Color(0xFFAB5236),   // brown
      surfaceContainerHighest: Color(0xFF83769C), // lavender
    ),
  ),

  // Game Boy DMG — 4 greens: 0F380F / 306230 / 8BAC0F / 9BBC0F
  ThemePreset(
    id: 'gameboy',
    name: 'Game Boy',
    seedColor: Color(0xFF8BAC0F),
    pixelPalette: KoheraPalette.gameboy,
    darkScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF8BAC0F),
      onPrimary: Color(0xFF0F380F),
      primaryContainer: Color(0xFF306230),
      onPrimaryContainer: Color(0xFF9BBC0F),
      secondary: Color(0xFF9BBC0F),
      onSecondary: Color(0xFF0F380F),
      secondaryContainer: Color(0xFF306230),
      onSecondaryContainer: Color(0xFF9BBC0F),
      tertiary: Color(0xFF8BAC0F),
      onTertiary: Color(0xFF0F380F),
      tertiaryContainer: Color(0xFF306230),
      onTertiaryContainer: Color(0xFF9BBC0F),
      error: Color(0xFF9BBC0F),
      onError: Color(0xFF0F380F),
      surface: Color(0xFF0F380F),
      onSurface: Color(0xFF9BBC0F),
      onSurfaceVariant: Color(0xFF8BAC0F),
      outline: Color(0xFF306230),
      outlineVariant: Color(0xFF306230),
      surfaceContainerLowest: Color(0xFF0A280A),
      surfaceContainerLow: Color(0xFF163E16),
      surfaceContainer: Color(0xFF1E4A1E),
      surfaceContainerHigh: Color(0xFF2A5A2A),
      surfaceContainerHighest: Color(0xFF306230),
    ),
    lightScheme: ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF0F380F),
      onPrimary: Color(0xFF9BBC0F),
      primaryContainer: Color(0xFF8BAC0F),
      onPrimaryContainer: Color(0xFF0F380F),
      secondary: Color(0xFF306230),
      onSecondary: Color(0xFF9BBC0F),
      secondaryContainer: Color(0xFF8BAC0F),
      onSecondaryContainer: Color(0xFF0F380F),
      tertiary: Color(0xFF306230),
      onTertiary: Color(0xFF9BBC0F),
      tertiaryContainer: Color(0xFF8BAC0F),
      onTertiaryContainer: Color(0xFF0F380F),
      error: Color(0xFF0F380F),
      onError: Color(0xFF9BBC0F),
      surface: Color(0xFF9BBC0F),
      onSurface: Color(0xFF0F380F),
      onSurfaceVariant: Color(0xFF306230),
      outline: Color(0xFF306230),
      outlineVariant: Color(0xFF8BAC0F),
      surfaceContainerLowest: Color(0xFFAECD33),
      surfaceContainerLow: Color(0xFF93B40F),
      surfaceContainer: Color(0xFF8BAC0F),
      surfaceContainerHigh: Color(0xFF6E9A1E),
      surfaceContainerHighest: Color(0xFF4F7A22),
    ),
  ),

  // Paper — ink on warm paper (light-native), designed dark "night paper"
  ThemePreset(
    id: 'paper',
    name: 'Paper',
    seedColor: Color(0xFFB0453A),
    pixelPalette: KoheraPalette.paper,
    lightScheme: ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFFB0453A),
      onPrimary: Color(0xFFFBF7EC),
      primaryContainer: Color(0xFFE8E0CC),
      onPrimaryContainer: Color(0xFF2B2620),
      secondary: Color(0xFF3A6EA5),
      onSecondary: Color(0xFFFBF7EC),
      secondaryContainer: Color(0xFFDCE4EC),
      onSecondaryContainer: Color(0xFF2B2620),
      tertiary: Color(0xFFC9A227),
      onTertiary: Color(0xFF2B2620),
      tertiaryContainer: Color(0xFFF0E6C6),
      onTertiaryContainer: Color(0xFF2B2620),
      error: Color(0xFFB0453A),
      onError: Color(0xFFFBF7EC),
      surface: Color(0xFFFBF7EC),
      onSurface: Color(0xFF2B2620),
      onSurfaceVariant: Color(0xFF6B6355),
      outline: Color(0xFF8A8070),
      outlineVariant: Color(0xFFDED5C0),
      surfaceContainerLowest: Color(0xFFFFFDF7),
      surfaceContainerLow: Color(0xFFF5EFE0),
      surfaceContainer: Color(0xFFEFE8D6),
      surfaceContainerHigh: Color(0xFFE8E0CC),
      surfaceContainerHighest: Color(0xFFDED5C0),
    ),
    darkScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFC46A5B),
      onPrimary: Color(0xFF15130F),
      primaryContainer: Color(0xFF2A2822),
      onPrimaryContainer: Color(0xFFEDE6D2),
      secondary: Color(0xFF7FA6C9),
      onSecondary: Color(0xFF15130F),
      secondaryContainer: Color(0xFF23262B),
      onSecondaryContainer: Color(0xFFEDE6D2),
      tertiary: Color(0xFFD9A441),
      onTertiary: Color(0xFF15130F),
      tertiaryContainer: Color(0xFF2A2822),
      onTertiaryContainer: Color(0xFFEDE6D2),
      error: Color(0xFFC46A5B),
      onError: Color(0xFF15130F),
      surface: Color(0xFF15130F),
      onSurface: Color(0xFFEDE6D2),
      onSurfaceVariant: Color(0xFFB5AD98),
      outline: Color(0xFF4A453B),
      outlineVariant: Color(0xFF2A2822),
      surfaceContainerLowest: Color(0xFF100E0B),
      surfaceContainerLow: Color(0xFF1C1A15),
      surfaceContainer: Color(0xFF1C1A15),
      surfaceContainerHigh: Color(0xFF2A2822),
      surfaceContainerHighest: Color(0xFF2A2822),
    ),
  ),

  // ── SNES ─────────────────────────────────────────────────────────────
  // 16-bit soft-beveled pixel theme (snes.css inspired). grey #e5e5e5
  // light surface (snes.css default canvas), aged-yellow #fcf4d9 as
  // surfaceContainerHighest elevated accent + dark onSurface text accent,
  // phantom purple #9b5de5 primary, dusk #2c3e50 text/border, 9-color ramp.
  ThemePreset(
    id: 'snes',
    name: 'SNES',
    seedColor: Color(0xFF9b5de5),
    pixelPalette: KoheraPalette.snes,
    darkScheme: ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF9b5de5),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFF5a3a8c),
      onPrimaryContainer: Color(0xFFFFFFFF),
      secondary: Color(0xFF4eb6d9),
      onSecondary: Color(0xFF000000),
      secondaryContainer: Color(0xFF2a6d8a),
      onSecondaryContainer: Color(0xFFFFFFFF),
      tertiary: Color(0xFFf2c019),
      onTertiary: Color(0xFF000000),
      tertiaryContainer: Color(0xFFb8900f),
      onTertiaryContainer: Color(0xFF000000),
      error: Color(0xFFf22561),
      onError: Color(0xFFFFFFFF),
      surface: Color(0xFF2c3e50),
      onSurface: Color(0xFFfcf4d9),
      onSurfaceVariant: Color(0xFF908a99),
      outline: Color(0xFF566573),
      outlineVariant: Color(0xFF3a4a5c),
      surfaceContainerLowest: Color(0xFF1f2c3a),
      surfaceContainerLow: Color(0xFF26333f),
      surfaceContainer: Color(0xFF2c3e50),
      surfaceContainerHigh: Color(0xFF384a5c),
      surfaceContainerHighest: Color(0xFF465868),
    ),
    lightScheme: ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF9b5de5),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFf0e4ff),
      onPrimaryContainer: Color(0xFF2c3e50),
      secondary: Color(0xFF4eb6d9),
      onSecondary: Color(0xFF000000),
      secondaryContainer: Color(0xFFd6f0f8),
      onSecondaryContainer: Color(0xFF2c3e50),
      tertiary: Color(0xFFf2c019),
      onTertiary: Color(0xFF2c3e50),
      tertiaryContainer: Color(0xFFfdf0b8),
      onTertiaryContainer: Color(0xFF2c3e50),
      error: Color(0xFFc41a4d),
      onError: Color(0xFFFFFFFF),
      surface: Color(0xFFe5e5e5),
      onSurface: Color(0xFF2c3e50),
      onSurfaceVariant: Color(0xFF566573),
      outline: Color(0xFF5a7d9a),
      outlineVariant: Color(0xFFb0a890),
      surfaceContainerLowest: Color(0xFFF5F5F5),
      surfaceContainerLow: Color(0xFFEDEDED),
      surfaceContainer: Color(0xFFE2E2E2),
      surfaceContainerHigh: Color(0xFFD8D8D8),
      surfaceContainerHighest: Color(0xFFfcf4d9),
    ),
  ),
];

final themePresets = Map<String, ThemePreset>.fromEntries(
  _presets.map((p) => MapEntry(p.id, p)),
);

List<ThemePreset> get themePresetList => _presets;

ThemePreset? getPreset(String? id) => id != null ? themePresets[id] : null;
