import 'package:flutter/material.dart';
import 'package:kohera/core/utils/openmoji.dart';

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

/// Regex matching common emoji characters and sequences (ZWJ, skin tones,
/// variation selectors). Uses Unicode ranges rather than `\p{Emoji}` which
/// is not supported by Dart's RegExp engine.
final _emojiRegex = RegExp(
  // Core emoji ranges + variation selector + ZWJ sequences + skin tone modifiers.
  r'(?:[\u{231A}-\u{23F3}\u{25AA}-\u{25FE}\u{2600}-\u{27BF}\u{2934}-\u{2935}\u{2B05}-\u{2B55}\u{3030}\u{303D}\u{1F000}-\u{1FAFF}]'
  r'[\uFE0E\uFE0F]?'
  r'(?:\u200D[\u{231A}-\u{23F3}\u{25AA}-\u{25FE}\u{2600}-\u{27BF}\u{2934}-\u{2935}\u{2B05}-\u{2B55}\u{3030}\u{303D}\u{1F000}-\u{1FAFF}][\uFE0E\uFE0F]?)*'
  r'[\u{1F3FB}-\u{1F3FF}]?)',
  unicode: true,
);

/// Default emoji-to-text size ratio used when [TextStyle.height] is unset.
const _defaultEmojiHeight = 1.2;

/// Whether [text] consists solely of emoji runs (optionally separated by
/// whitespace) and at least one emoji. Used to enlarge emoji-only messages.
bool isEmojiOnly(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;

  var matchedAny = false;
  var cursor = 0;
  for (final m in _emojiRegex.allMatches(trimmed)) {
    if (trimmed.substring(cursor, m.start).trim().isNotEmpty) return false;
    matchedAny = true;
    cursor = m.end;
  }
  if (trimmed.substring(cursor).trim().isNotEmpty) return false;
  return matchedAny;
}

/// Splits [text] into [InlineSpan]s, rendering each detected emoji run as an
/// OpenMoji image ([WidgetSpan]) sized to the surrounding line height. Runs
/// without a bundled OpenMoji asset fall back to [emojiFontFallback] text so
/// regular text keeps its normal font metrics and no tofu is shown.
List<InlineSpan> buildEmojiSpans(String text, TextStyle? style) {
  final matches = _emojiRegex.allMatches(text).toList();
  if (matches.isEmpty) {
    return [TextSpan(text: text, style: style)];
  }

  final spans = <InlineSpan>[];
  var lastEnd = 0;

  for (final m in matches) {
    if (m.start > lastEnd) {
      spans.add(TextSpan(text: text.substring(lastEnd, m.start), style: style));
    }
    spans.add(_emojiSpan(m.group(0)!, style));
    lastEnd = m.end;
  }

  if (lastEnd < text.length) {
    spans.add(TextSpan(text: text.substring(lastEnd), style: style));
  }

  return spans;
}

/// Builds the span for a single emoji [run]: an OpenMoji image when one is
/// bundled, otherwise a font-fallback [TextSpan].
InlineSpan _emojiSpan(String run, TextStyle? style) {
  final asset = openMojiAssetFor(run);
  if (asset == null) return _fallbackSpan(run, style);

  final fontSize = style?.fontSize ?? 14;
  final size = fontSize * (style?.height ?? _defaultEmojiHeight);
  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) =>
          Text.rich(_fallbackSpan(run, style)),
    ),
  );
}

TextSpan _fallbackSpan(String run, TextStyle? style) => TextSpan(
      text: run,
      style: (style ?? const TextStyle())
          .copyWith(fontFamilyFallback: emojiFontFallback),
    );
