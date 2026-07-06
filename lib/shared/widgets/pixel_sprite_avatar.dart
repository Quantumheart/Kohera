import 'package:flutter/material.dart';
import 'package:kohera/core/theme/kohera_palette.dart';

/// A deterministic, symmetric pixel-art sprite used as the no-avatar fallback.
///
/// The pattern and colour are derived from [seed] (a room id / user id / name)
/// so the same entity always renders the same sprite. Colours come from the
/// active [KoheraPalette.accentRamp] so the sprite matches the current theme.
class PixelSpriteAvatar extends StatelessWidget {
  const PixelSpriteAvatar({
    required this.seed,
    required this.size,
    super.key,
  });

  final String seed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ramp = Theme.of(context).extension<KoheraPalette>()?.accentRamp ??
        <Color>[cs.primary];
    final hash = _fnv1a(seed);
    final fg = ramp[hash % ramp.length];
    final bg = Color.alphaBlend(const Color(0xD1000000), fg);

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SpritePainter(hash: hash, fg: fg, bg: bg),
      ),
    );
  }

  static int _fnv1a(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7fffffff;
    }
    return h;
  }
}

class _SpritePainter extends CustomPainter {
  _SpritePainter({required this.hash, required this.fg, required this.bg});

  final int hash;
  final Color fg;
  final Color bg;

  static const _grid = 7;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    final cell = size.width / _grid;
    final paint = Paint()..color = fg;
    const half = (_grid + 1) ~/ 2; // left columns incl. centre, then mirrored
    for (var y = 1; y < _grid - 1; y++) {
      for (var x = 0; x < half; x++) {
        final on = (hash >> ((y * half + x) % 31)) & 1;
        if (on == 1) {
          _cell(canvas, paint, cell, x, y);
          _cell(canvas, paint, cell, _grid - 1 - x, y);
        }
      }
    }
  }

  void _cell(Canvas canvas, Paint paint, double cell, int x, int y) {
    // +0.6 overlap avoids hairline seams between cells at fractional sizes.
    canvas.drawRect(
      Rect.fromLTWH(x * cell, y * cell, cell + 0.6, cell + 0.6),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SpritePainter old) =>
      old.hash != hash || old.fg != fg || old.bg != bg;
}
