import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:kohera/core/theme/kohera_palette.dart';

class CustomTheme {
  const CustomTheme({
    required this.background,
    required this.foreground,
    required this.primary,
    required this.secondary,
    required this.muted,
    required this.border,
    required this.highlight,
  });

  final Color background;
  final Color foreground;
  final Color primary;
  final Color secondary;
  final Color muted;
  final Color border;
  final Color highlight;

  static const defaults = CustomTheme(
    background: Color(0xFF1E1E2E), // koheraPalette.surface
    foreground: Color(0xFFCDD6F4), // koheraPalette.onSurface
    primary: Color(0xFF89B4FA), // koheraPalette.primary
    secondary: Color(0xFF585B70), // koheraPalette.secondary
    muted: Color(0xFFA6ADC8), // koheraPalette.onSurfaceVariant
    border: Color(0xFF45475A), // koheraPalette.borderStrong
    highlight: Color(0xFFF9E2AF), // koheraPalette.tertiary
  );

  CustomTheme copyWith({
    Color? background,
    Color? foreground,
    Color? primary,
    Color? secondary,
    Color? muted,
    Color? border,
    Color? highlight,
  }) => CustomTheme(
    background: background ?? this.background,
    foreground: foreground ?? this.foreground,
    primary: primary ?? this.primary,
    secondary: secondary ?? this.secondary,
    muted: muted ?? this.muted,
    border: border ?? this.border,
    highlight: highlight ?? this.highlight,
  );

  // ── ColorScheme generation ───────────────────────────────────

  ColorScheme toColorScheme(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    return ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: _contrastOn(primary),
      primaryContainer: _shift(primary, isLight ? 0.85 : 0.3),
      onPrimaryContainer: _shift(primary, isLight ? 0.15 : 0.9),
      secondary: secondary,
      onSecondary: _contrastOn(secondary),
      secondaryContainer: _shift(secondary, isLight ? 0.85 : 0.3),
      onSecondaryContainer: _shift(secondary, isLight ? 0.15 : 0.9),
      tertiary: highlight,
      onTertiary: _contrastOn(highlight),
      tertiaryContainer: _shift(highlight, isLight ? 0.85 : 0.3),
      onTertiaryContainer: _shift(highlight, isLight ? 0.15 : 0.9),
      error: const Color(0xFFF38BA8), // koheraPalette.error
      onError: const Color(0xFF1E1E2E), // koheraPalette.onError
      surface: background,
      onSurface: foreground,
      onSurfaceVariant: muted,
      outline: border,
      outlineVariant: _shift(border, isLight ? 0.8 : 0.4),
      surfaceContainerLowest: _shift(background, isLight ? 1.0 : 0.0),
      surfaceContainerLow: _shift(background, isLight ? 0.96 : 0.08),
      surfaceContainer: _shift(background, isLight ? 0.92 : 0.12),
      surfaceContainerHigh: _shift(background, isLight ? 0.88 : 0.17),
      surfaceContainerHighest: _shift(background, isLight ? 0.84 : 0.22),
    );
  }

  static Color _contrastOn(Color color) =>
      ThemeData.estimateBrightnessForColor(color) == Brightness.dark
          ? Colors.white
          : Colors.black;

  static Color _shift(Color color, double t) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + (t - 0.5) * 0.3).clamp(0, 1)).toColor();
  }

  // ── Serialization ────────────────────────────────────────────

  String toJsonString() => jsonEncode({
    'background': background.toARGB32(),
    'foreground': foreground.toARGB32(),
    'primary': primary.toARGB32(),
    'secondary': secondary.toARGB32(),
    'muted': muted.toARGB32(),
    'border': border.toARGB32(),
    'highlight': highlight.toARGB32(),
  });

  factory CustomTheme.fromJsonString(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return CustomTheme(
      background: Color(map['background'] as int),
      foreground: Color(map['foreground'] as int),
      primary: Color(map['primary'] as int),
      secondary: Color(map['secondary'] as int),
      muted: Color(map['muted'] as int),
      border: Color(map['border'] as int),
      highlight: Color(map['highlight'] as int),
    );
  }
  
  /// Converts this custom theme to a KoheraPalette
  KoheraPalette toKoheraPalette(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    
    // For a custom theme, we'll map the colors to the closest palette tokens
    return KoheraPalette(
      borderStrong: border,
      borderWidth: 2,
      shadowHard: isLight ? const Color(0xFF7E2553) : const Color(0xFF7E2553), // PICO-8 dark purple
      shadowOffset: 3,
      radius: 0,
      online: const Color(0xFF00E436), // PICO-8 green
      idle: const Color(0xFFFFA300), // PICO-8 orange
      unread: const Color(0xFFFF77A8), // PICO-8 pink
      onUnread: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
      mention: const Color(0xFFFFEC27), // PICO-8 yellow
      link: const Color(0xFF29ADFF), // PICO-8 blue
      ownBubble: isLight ? const Color(0xFF0B2B3F) : const Color(0xFF0B2B3F),
      onOwnBubble: isLight ? const Color(0xFFFFFFFF) : const Color(0xFFFFFFFF),
      otherBubble: isLight ? const Color(0xFF0E1638) : const Color(0xFF0E1638),
      onOtherBubble: isLight ? const Color(0xFFFFFFFF) : const Color(0xFFFFFFFF),
      success: const Color(0xFF00E436), // PICO-8 green
      warning: const Color(0xFFFFA300), // PICO-8 orange
      danger: const Color(0xFFFF004D), // PICO-8 red
      scanline: const Color(0xFF000000).withValues(alpha: 0.18),
      dither: const Color(0xFF1D2B53), // PICO-8 dark blue
      accentRamp: [
        const Color(0xFFFF77A8), // PICO-8 pink
        const Color(0xFF29ADFF), // PICO-8 blue
        const Color(0xFF83769C), // PICO-8 lavender
        const Color(0xFF00E436), // PICO-8 green
        const Color(0xFFFFA300), // PICO-8 orange
        const Color(0xFFFFEC27), // PICO-8 yellow
      ],
    );
  }
}
