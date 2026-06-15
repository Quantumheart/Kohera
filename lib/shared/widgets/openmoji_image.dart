import 'package:flutter/material.dart';
import 'package:kohera/core/utils/emoji_style.dart';
import 'package:kohera/core/utils/openmoji.dart';

/// Renders a single emoji [grapheme] using the bundled OpenMoji color font,
/// falling back to system-font text when the grapheme is not in the OpenMoji
/// set. This is the single shared OpenMoji render+fallback path used by both
/// inline message text ([buildEmojiSpans]) and the picker grid.
class OpenMojiImage extends StatelessWidget {
  const OpenMojiImage({
    required this.grapheme,
    super.key,
    this.size,
    this.fallbackStyle,
  });

  /// The Unicode emoji to render.
  final String grapheme;

  /// Square edge length. When null the glyph fills its parent's constraints
  /// (used by the picker grid cells).
  final double? size;

  /// Style applied to the text fallback.
  final TextStyle? fallbackStyle;

  @override
  Widget build(BuildContext context) {
    if (openMojiNameFor(grapheme) == null) return _fallback();

    final s = size;
    if (s != null) {
      // Pin the painted box so inline emoji (WidgetSpan, reaction chips) cannot
      // blow out the layout, and centre the glyph within it.
      return SizedBox(
        width: s,
        height: s,
        child: Center(child: _glyph(s)),
      );
    }
    // Fill the parent (picker grid cells): size the glyph to the shorter side.
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        return Center(child: _glyph(side.isFinite && side > 0 ? side : 24));
      },
    );
  }

  Widget _glyph(double fontSize) => ExcludeSemantics(
        child: Text(
          grapheme,
          textAlign: TextAlign.center,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: TextStyle(
            fontFamily: openMojiFontFamily,
            fontFamilyFallback: emojiFontFallback,
            fontSize: fontSize,
            height: 1,
          ),
        ),
      );

  Widget _fallback() => Text(
        grapheme,
        style: emojiTextStyle.merge(fallbackStyle),
      );
}
