import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:kohera/core/theme/kohera_palette.dart';

/// Effective bubble tokens after interpolating between the retro (vibe=0)
/// and modern (vibe=1) endpoints.
///
/// At `vibe = 0.0` the values are bit-identical to the raw [KoheraPalette]
/// tokens, so existing themes and goldens are unaffected.
class EffectiveBubbleTokens {
  const EffectiveBubbleTokens({
    required this.radius,
    required this.borderWidth,
    required this.borderColor,
    required this.shadowOffset,
    required this.shadowBlur,
    required this.shadowColor,
    required this.highlightAlpha,
  });

  /// Corner radius for the bubble.
  final double radius;

  /// Border line width.
  final double borderWidth;

  /// Border color.
  final Color borderColor;

  /// Shadow displacement (already a full [Offset]).
  final Offset shadowOffset;

  /// Gaussian blur radius for the shadow (0 = hard offset shadow).
  final double shadowBlur;

  /// Shadow color.
  final Color shadowColor;

  /// Alpha for an optional top-edge highlight (bevel). 0 = none.
  final double highlightAlpha;

  @override
  String toString() =>
      'EffectiveBubbleTokens(radius=$radius, borderWidth=$borderWidth, '
      'borderColor=$borderColor, shadowOffset=$shadowOffset, '
      'shadowBlur=$shadowBlur, shadowColor=$shadowColor, '
      'highlightAlpha=$highlightAlpha)';
}

/// Resolves effective bubble tokens by interpolating between the current
/// pixel-retro palette (vibe = 0) and a rounded soft-shadow modern look
/// (vibe = 1).
///
/// The palette's own identity colours (bubble fill, text) are never changed —
/// only shape and shadow morph.
class BubbleVibeResolver {
  /// Modern endpoint constants.
  static const modernRadius = 16.0;
  static const modernBorderWidth = 0.0;
  static const modernShadowBlur = 12.0;
  static const modernShadowOffset = 0.0;
  static const modernHighlightAlpha = 0.0;

  /// Resolve [EffectiveBubbleTokens] for [palette] at [vibe] (0.0–1.0).
  ///
  /// At `vibe = 0.0` the result matches `palette` tokens exactly.
  static EffectiveBubbleTokens resolve(
    KoheraPalette palette,
    double vibe,
  ) {
    final clamped = vibe.clamp(0.0, 1.0);

    return EffectiveBubbleTokens(
      radius: lerpDouble(palette.radius, modernRadius, clamped)!,
      borderWidth: lerpDouble(palette.borderWidth, modernBorderWidth, clamped)!,
      borderColor:
          Color.lerp(palette.borderStrong, Colors.transparent, clamped)!,
      shadowOffset: Offset(
        lerpDouble(palette.shadowOffset, modernShadowOffset, clamped)!,
        lerpDouble(palette.shadowOffset, modernShadowOffset, clamped)!,
      ),
      shadowBlur: lerpDouble(0.0, modernShadowBlur, clamped)!,
      shadowColor: Color.lerp(
        palette.shadowHard,
        palette.shadowHard.withValues(alpha: 0.3),
        clamped,
      )!,
      highlightAlpha: lerpDouble(0.0, modernHighlightAlpha, clamped)!,
    );
  }
}
