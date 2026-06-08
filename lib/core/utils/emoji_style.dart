import 'package:flutter/painting.dart';

/// Fallback font families for rendering color emoji on desktop platforms.
const emojiFontFallback = [
  'Noto Color Emoji',
  'Apple Color Emoji',
  'Segoe UI Emoji',
];

/// Text style for rendering emoji as text (the fallback when no OpenMoji asset
/// is bundled). Applies [emojiFontFallback] so color emoji resolve on every
/// platform.
const emojiTextStyle = TextStyle(fontFamilyFallback: emojiFontFallback);
