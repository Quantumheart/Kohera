import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kohera/core/theme/kohera_palette.dart';

/// The Kohera wordmark: a custom pixeled "K" glyph (signature accent color) +
/// "ohera" in PressStart2P. See `plans/brand_wordmark_brief.md`.
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

  /// PressStart2P font size for "ohera"; the pixeled "K" is scaled to match.
  final double size;

  /// Whether to tint the "K" with the active palette's accent ramp[0].
  final bool colored;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<KoheraPalette>();
    final kColor =
        (colored && palette != null && palette.accentRamp.isNotEmpty)
            ? palette.accentRamp.first
            : cs.onSurface;

    // The pixeled "K" SVG is a 16×16 box whose glyph drawing fills ~13/16 of
    // the box vertically — close to PressStart2P's cap height — so rendering
    // the box at `size` matches the text cap height. Letter spacing comes
    // from the glyph's natural right bearing; a small gap separates it from
    // "ohera".
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: size,
          width: size,
          child: SvgPicture.asset(
            'assets/icons/kohera_glyph_k.svg',
            colorFilter: ColorFilter.mode(kColor, BlendMode.srcIn),
          ),
        ),
        const SizedBox(width: 2),
        Text(
          'ohera',
          style: TextStyle(
            fontFamily: 'PressStart2P',
            fontSize: size,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}
