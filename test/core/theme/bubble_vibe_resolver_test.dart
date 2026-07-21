import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/theme/bubble_vibe_resolver.dart';
import 'package:kohera/core/theme/kohera_palette.dart';

/// A minimal PICO-8-like palette for testing.
KoheraPalette _testPalette() => const KoheraPalette(
      borderStrong: Color(0xFF000000),
      borderWidth: 2,
      shadowHard: Color(0xFF7E2553),
      shadowOffset: 3,
      radius: 0,
      online: Colors.green,
      idle: Colors.amber,
      unread: Colors.red,
      onUnread: Colors.white,
      mention: Colors.orange,
      link: Colors.blue,
      ownBubble: Color(0xFF0B2B3F),
      onOwnBubble: Colors.white,
      otherBubble: Color(0xFF0E1638),
      onOtherBubble: Colors.white,
      success: Colors.green,
      warning: Colors.amber,
      danger: Colors.red,
      scanline: Colors.black12,
      dither: Colors.black12,
      accentRamp: [Colors.blue],
    );

void main() {
  group('BubbleVibeResolver', () {
    test('vibe 0.0 matches palette tokens exactly (retro)', () {
      final palette = _testPalette();
      final eff = BubbleVibeResolver.resolve(palette, 0);

      expect(eff.radius, palette.radius);
      expect(eff.borderWidth, palette.borderWidth);
      expect(eff.borderColor, palette.borderStrong);
      expect(eff.shadowOffset,
          Offset(palette.shadowOffset, palette.shadowOffset));
      expect(eff.shadowBlur, 0);
      expect(eff.shadowColor, palette.shadowHard);
      expect(eff.highlightAlpha, 0);
    });

    test('vibe 1.0 produces modern endpoint values', () {
      final palette = _testPalette();
      final eff = BubbleVibeResolver.resolve(palette, 1);

      expect(eff.radius, BubbleVibeResolver.modernRadius);
      expect(eff.borderWidth, BubbleVibeResolver.modernBorderWidth);
      expect(eff.borderColor, Colors.transparent);
      expect(eff.shadowOffset, Offset.zero);
      expect(eff.shadowBlur, BubbleVibeResolver.modernShadowBlur);
      expect(eff.shadowColor,
          palette.shadowHard.withValues(alpha: 0.3));
      expect(eff.highlightAlpha, BubbleVibeResolver.modernHighlightAlpha);
    });

    test('vibe 0.5 interpolates midway between retro and modern', () {
      final palette = _testPalette();
      final eff = BubbleVibeResolver.resolve(palette, 0.5);

      // Midpoint of radius 0 and 16 = 8
      expect(eff.radius, closeTo(8, 0.01));
      // Midpoint of borderWidth 2 and 0 = 1
      expect(eff.borderWidth, closeTo(1, 0.01));
      // Midpoint of shadowBlur 0 and 12 = 6
      expect(eff.shadowBlur, closeTo(6, 0.01));
    });

    test('clamps vibe below 0.0 to 0.0', () {
      final palette = _testPalette();
      final eff = BubbleVibeResolver.resolve(palette, -1);

      expect(eff.radius, palette.radius);
      expect(eff.shadowBlur, 0);
    });

    test('clamps vibe above 1.0 to 1.0', () {
      final palette = _testPalette();
      final eff = BubbleVibeResolver.resolve(palette, 2);

      expect(eff.radius, BubbleVibeResolver.modernRadius);
      expect(eff.shadowBlur, BubbleVibeResolver.modernShadowBlur);
    });
  });
}
