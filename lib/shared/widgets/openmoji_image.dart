import 'package:flutter/material.dart';
import 'package:kohera/core/utils/emoji_style.dart';
import 'package:kohera/core/utils/openmoji.dart';

/// Edge length in pixels of the bundled OpenMoji source assets.
const _openMojiSourcePx = 72;

/// Renders a single emoji [grapheme] as its bundled OpenMoji image, falling
/// back to system-font text when no asset is bundled or the asset fails to
/// load. This is the single shared OpenMoji render+fallback path used by both
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

  /// Square edge length. When null the image fills its parent's constraints
  /// (used by the picker grid cells).
  final double? size;

  /// Style applied to the text fallback.
  final TextStyle? fallbackStyle;

  @override
  Widget build(BuildContext context) {
    final asset = openMojiAssetFor(grapheme);
    if (asset == null) return _fallback();

    final s = size;
    // Resize at decode time so small targets (reaction chips, inline emoji) are
    // downsampled with the decoder's high-quality resampling instead of being
    // shrunk ~4x from the 72px source at draw time, which looks blurry. Cap the
    // decode at the native source size so larger paints still upscale from the
    // full 72px (avoids the blocky decode that motivated dropping cacheWidth).
    final cacheSize = s == null
        ? null
        : (s * (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0))
            .round()
            .clamp(1, _openMojiSourcePx);
    final image = Image.asset(
      asset,
      width: s,
      height: s,
      fit: BoxFit.contain,
      cacheWidth: cacheSize,
      cacheHeight: cacheSize,
      errorBuilder: (context, error, stackTrace) => _fallback(),
    );
    if (s == null) return image;
    // Pin the painted box. Inside a WidgetSpan (inline emoji, reaction chips)
    // the web renderer can ignore Image.width/height and paint the asset at its
    // native 72px, blowing out the layout; an explicit SizedBox constrains it.
    return SizedBox(width: s, height: s, child: image);
  }

  Widget _fallback() => Text(
        grapheme,
        style: emojiTextStyle.merge(fallbackStyle),
      );
}

/// Warms the image cache for [graphemes] (e.g. the quick-react set) so they
/// render without a decode hitch the first time they appear.
Future<void> precacheOpenMoji(
  BuildContext context,
  Iterable<String> graphemes,
) async {
  for (final g in graphemes) {
    final asset = openMojiAssetFor(g);
    if (asset != null) {
      await precacheImage(AssetImage(asset), context);
    }
  }
}
