import 'package:flutter/material.dart';
import 'package:kohera/core/theme/kohera_palette.dart';

/// The Kohera wordmark: "Kohera" in `PressStart2P`, with the leading "K"
/// tinted by the active palette's `accentRamp[0]`. See
/// `plans/brand_wordmark_brief.md`.
///
/// The "K" uses `KoheraPalette.accentRamp[0]` when `colored` and a palette is
/// present, tying the wordmark to the colorized mark's outer threads (#2). When
/// no palette is available (bare ThemeData, tests) it falls back to
/// `onSurface`, matching the legacy monochrome behavior.
class KoheraWordmark extends StatelessWidget {
  const KoheraWordmark({
    required this.size,
    this.colored = true,
    super.key,
  });

  /// PressStart2P font size for the wordmark.
  final double size;

  /// Whether to tint the leading "K" with the active palette's accent ramp[0].
  final bool colored;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<KoheraPalette>();
    final kColor =
        (colored && palette != null && palette.accentRamp.isNotEmpty)
            ? palette.accentRamp.first
            : cs.onSurface;

    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: 'PressStart2P',
          fontSize: size,
          fontWeight: FontWeight.w700,
        ),
        children: [
          TextSpan(text: 'K', style: TextStyle(color: kColor)),
          TextSpan(text: 'ohera', style: TextStyle(color: cs.onSurface)),
        ],
      ),
    );
  }
}
