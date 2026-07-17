import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/theme/kohera_theme.dart';
import 'package:kohera/core/theme/theme_presets.dart';

/// Regression guard: the pixel presets must produce distinct light and dark
/// themes so they respect the user's Light/Dark/System selection rather than
/// rendering a single fixed brightness.
///
/// Each pixel preset (PICO-8, Game Boy, Paper, SNES) declares both a `lightScheme`
/// and a `darkScheme`, no `forcedMode`, and a brightness-aware `pixelPalette`.
/// These tests pin that contract so a future change cannot silently collapse
/// the two modes into one.
void main() {
  const pixelPresets = ['pico8', 'gameboy', 'paper', 'snes'];

  for (final id in pixelPresets) {
    final preset = getPreset(id)!;

    group('$id preset respects light/dark mode', () {
      test('has no forcedMode (user mode selection is honoured)', () {
        expect(preset.forcedMode, isNull,
            reason: '$id must not force a brightness; the picker should drive '
                'the mode.');
      });

      test('declares both a light and a dark ColorScheme', () {
        expect(preset.lightScheme, isNotNull,
            reason: '$id must define a lightScheme.');
        expect(preset.darkScheme, isNotNull,
            reason: '$id must define a darkScheme.');
      });

      test('light and dark themes differ in brightness and surface', () {
        final light = KoheraTheme.light(preset: preset);
        final dark = KoheraTheme.dark(preset: preset);

        expect(light.brightness, Brightness.light);
        expect(dark.brightness, Brightness.dark);
        expect(
          light.scaffoldBackgroundColor,
          isNot(equals(dark.scaffoldBackgroundColor)),
          reason: '$id light/dark scaffold backgrounds must differ.',
        );
      });

      test('pixel palette differs by brightness', () {
        final lightPal = preset.pixelPalette!(Brightness.light);
        final darkPal = preset.pixelPalette!(Brightness.dark);

        expect(
          lightPal.ownBubble,
          isNot(equals(darkPal.ownBubble)),
          reason: '$id palette ownBubble must differ by brightness.',
        );
        expect(
          lightPal.otherBubble,
          isNot(equals(darkPal.otherBubble)),
          reason: '$id palette otherBubble must differ by brightness.',
        );
      });
    });
  }
}
