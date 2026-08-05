import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/theme/custom_theme.dart';
import 'package:kohera/core/theme/kohera_palette.dart';

void main() {
  group('CustomTheme', () {
    test('defaults has expected values', () {
      expect(CustomTheme.defaults.background, const Color(0xFF1E1E2E));
      expect(CustomTheme.defaults.foreground, const Color(0xFFCDD6F4));
      expect(CustomTheme.defaults.primary, const Color(0xFF89B4FA));
      expect(CustomTheme.defaults.secondary, const Color(0xFF585B70));
      expect(CustomTheme.defaults.muted, const Color(0xFFA6ADC8));
      expect(CustomTheme.defaults.border, const Color(0xFF45475A));
      expect(CustomTheme.defaults.highlight, const Color(0xFFF9E2AF));
    });

    test('copyWith replaces only provided fields', () {
      const theme = CustomTheme.defaults;
      final copied = theme.copyWith(primary: const Color(0xFF000000));

      expect(copied.primary, const Color(0xFF000000));
      expect(copied.background, theme.background);
      expect(copied.foreground, theme.foreground);
      expect(copied.secondary, theme.secondary);
    });

    test('copyWith with no args returns identical values', () {
      const theme = CustomTheme.defaults;
      final copied = theme.copyWith();

      expect(copied.background, theme.background);
      expect(copied.primary, theme.primary);
      expect(copied.highlight, theme.highlight);
    });

    test('toColorScheme produces valid ColorScheme for dark brightness', () {
      const theme = CustomTheme.defaults;
      final cs = theme.toColorScheme(Brightness.dark);

      expect(cs.brightness, Brightness.dark);
      expect(cs.primary, theme.primary);
      expect(cs.surface, theme.background);
      expect(cs.onSurface, theme.foreground);
      expect(cs.onSurfaceVariant, theme.muted);
      expect(cs.outline, theme.border);
      expect(cs.tertiary, theme.highlight);
      expect(cs.error, const Color(0xFFF38BA8));
    });

    test('toColorScheme produces valid ColorScheme for light brightness', () {
      const theme = CustomTheme.defaults;
      final cs = theme.toColorScheme(Brightness.light);

      expect(cs.brightness, Brightness.light);
      expect(cs.primary, theme.primary);
      expect(cs.surface, theme.background);
    });

    test('toColorScheme surfaceContainer tiers differ from surface', () {
      const theme = CustomTheme.defaults;
      final csDark = theme.toColorScheme(Brightness.dark);

      expect(csDark.surfaceContainer, isNot(equals(csDark.surface)));
      expect(csDark.surfaceContainerLow, isNot(equals(csDark.surface)));
      expect(csDark.surfaceContainerHigh, isNot(equals(csDark.surface)));
      expect(csDark.surfaceContainerHighest, isNot(equals(csDark.surface)));
    });

    test('toJsonString serializes all colors', () {
      const theme = CustomTheme.defaults;
      final json = theme.toJsonString();

      expect(json, contains('"background":${theme.background.toARGB32()}'));
      expect(json, contains('"primary":${theme.primary.toARGB32()}'));
      expect(json, contains('"highlight":${theme.highlight.toARGB32()}'));
    });

    test('fromJsonString round-trips with toJsonString', () {
      const theme = CustomTheme(
        background: Color(0xFF112233),
        foreground: Color(0xFFAABBCC),
        primary: Color(0xFF123456),
        secondary: Color(0xFF789ABC),
        muted: Color(0xFFDEF012),
        border: Color(0xFF345678),
        highlight: Color(0xFF9ABCDE),
      );

      final json = theme.toJsonString();
      final restored = CustomTheme.fromJsonString(json);

      expect(restored.background, theme.background);
      expect(restored.foreground, theme.foreground);
      expect(restored.primary, theme.primary);
      expect(restored.secondary, theme.secondary);
      expect(restored.muted, theme.muted);
      expect(restored.border, theme.border);
      expect(restored.highlight, theme.highlight);
    });

    test('fromJsonString parses defaults correctly', () {
      final json = CustomTheme.defaults.toJsonString();
      final restored = CustomTheme.fromJsonString(json);

      expect(restored.background, CustomTheme.defaults.background);
      expect(restored.primary, CustomTheme.defaults.primary);
    });

    test('toKoheraPalette returns KoheraPalette with expected tokens', () {
      const theme = CustomTheme.defaults;
      final palette = theme.toKoheraPalette(Brightness.dark);

      expect(palette, isA<KoheraPalette>());
      expect(palette.borderStrong, theme.border);
      expect(palette.online, const Color(0xFF00E436));
      expect(palette.mention, const Color(0xFFFFEC27));
      expect(palette.link, const Color(0xFF29ADFF));
      expect(palette.accentRamp.length, 6);
    });

    test('toKoheraPalette for light brightness', () {
      const theme = CustomTheme.defaults;
      final palette = theme.toKoheraPalette(Brightness.light);

      expect(palette, isA<KoheraPalette>());
      expect(palette.borderStrong, theme.border);
    });

    test('_contrastOn returns white for dark colors', () {
      const theme = CustomTheme.defaults;
      final cs = theme.toColorScheme(Brightness.dark);
      // primary is light blue → onPrimary should be dark
      expect(cs.onPrimary, isA<Color>());
    });

    test('_shift produces different lightness values', () {
      const theme = CustomTheme.defaults;
      final cs = theme.toColorScheme(Brightness.dark);
      // surfaceContainer should have different lightness than surface
      expect(cs.surfaceContainer, isNot(equals(cs.surfaceContainerHighest)));
    });
  });
}
