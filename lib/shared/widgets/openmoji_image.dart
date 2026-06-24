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
    // Decode with 2x headroom over the physical target so small paints (reaction
    // chips, inline emoji) keep detail, then let Image's default medium-quality
    // resampling downsample to the logical size. Decoding straight to the ~17px
    // target box leaves nothing to filter and looks blocky. Cap the decode at the
    // native source size so larger paints still upscale from the full 72px.
    final cacheSize = s == null
        ? null
        : (s * (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0) * 2)
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
    if (!context.mounted) return;
    final asset = openMojiAssetFor(g);
    if (asset != null) {
      await precacheImage(AssetImage(asset), context);
    }
  }
}
