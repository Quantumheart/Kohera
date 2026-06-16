import 'package:flutter/foundation.dart';
import 'package:kohera/core/utils/openmoji_manifest.g.dart';

/// Font family of the bundled OpenMoji color font (`assets/fonts`, declared in
/// `pubspec.yaml`). Emoji in [kOpenMojiNames] render through this family;
/// anything else falls back to the platform emoji font.
const openMojiFontFamily = 'OpenMoji';

/// Whether to render emoji through the bundled OpenMoji COLRv1 color font.
///
/// Disabled on native iOS: the Impeller renderer does not paint COLRv1 color
/// glyphs, so the selected OpenMoji glyph renders blank (transparent) rather
/// than falling through to the platform emoji font. There we render emoji with
/// the system color emoji font instead. Flutter web (CanvasKit/Skia, even on
/// iOS Safari) and every other platform render COLRv1 correctly.
bool get useBundledOpenMoji =>
    kIsWeb || defaultTargetPlatform != TargetPlatform.iOS;

const _variationSelectors = {0xFE0E, 0xFE0F};

/// A Unicode skin-tone modifier (Fitzpatrick scale), or [none] for the default
/// yellow rendering.
enum SkinTone {
  none,
  light,
  mediumLight,
  medium,
  mediumDark,
  dark;

  /// The Unicode modifier codepoint (`U+1F3FB`–`U+1F3FF`), or null for [none].
  int? get modifier => switch (this) {
        SkinTone.none => null,
        SkinTone.light => 0x1F3FB,
        SkinTone.mediumLight => 0x1F3FC,
        SkinTone.medium => 0x1F3FD,
        SkinTone.mediumDark => 0x1F3FE,
        SkinTone.dark => 0x1F3FF,
      };

  String get label => switch (this) {
        SkinTone.none => 'Default',
        SkinTone.light => 'Light',
        SkinTone.mediumLight => 'Medium-light',
        SkinTone.medium => 'Medium',
        SkinTone.mediumDark => 'Medium-dark',
        SkinTone.dark => 'Dark',
      };

  /// A sample toned emoji (raised hand) for swatches.
  String get sample => applySkinTone('\u{270B}', this);
}

/// Returns [grapheme] with [tone] applied, inserting the modifier after the
/// leading codepoint. Falls back to [grapheme] when [tone] is [SkinTone.none]
/// or the toned variant has no bundled asset (so it is safe to call on any
/// emoji).
String applySkinTone(String grapheme, SkinTone tone) {
  final modifier = tone.modifier;
  if (modifier == null) return grapheme;

  final runes =
      grapheme.runes.where((c) => !_variationSelectors.contains(c)).toList();
  if (runes.isEmpty) return grapheme;

  final toned = String.fromCharCodes([runes.first, modifier, ...runes.skip(1)]);
  return openMojiNameFor(toned) != null ? toned : grapheme;
}

/// Whether [grapheme] has at least one bundled skin-tone variant.
bool openMojiSupportsSkinTone(String grapheme) =>
    applySkinTone(grapheme, SkinTone.light) != grapheme;

/// Codepoint sequence base name for [grapheme] following OpenMoji's filename
/// convention: uppercase hex codepoints joined by `-`.
String _name(Iterable<int> codepoints) => codepoints
    .map((c) => c.toRadixString(16).toUpperCase().padLeft(4, '0'))
    .join('-');

/// Resolves the OpenMoji asset base name (no extension) for a single emoji
/// [grapheme], or `null` when no matching asset exists.
///
/// OpenMoji is inconsistent about variation selectors — keycaps keep `U+FE0F`
/// (`0023-FE0F-20E3`) while most others drop it (`2764`). So we try the literal
/// sequence first, then the sequence with variation selectors removed.
String? openMojiNameFor(String grapheme) {
  final runes = grapheme.runes.toList();
  if (runes.isEmpty) return null;

  final asIs = _name(runes);
  if (kOpenMojiNames.contains(asIs)) return asIs;

  final stripped = _name(runes.where((c) => !_variationSelectors.contains(c)));
  if (stripped != asIs && kOpenMojiNames.contains(stripped)) return stripped;

  return null;
}
