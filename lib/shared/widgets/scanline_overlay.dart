import 'package:flutter/material.dart';
import 'package:kohera/core/theme/kohera_palette.dart';

/// Paints faint horizontal CRT scanlines over [child] using the active
/// [KoheraPalette.scanline] tint.
///
/// Renders nothing extra when [enabled] is false, when the token is fully
/// transparent, or when the platform requests reduced motion / disabled
/// animations (accessibility).
class ScanlineOverlay extends StatelessWidget {
  const ScanlineOverlay({
    required this.child,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final tint = Theme.of(context).extension<KoheraPalette>()?.scanline;

    if (!enabled || reduceMotion || tint == null || tint.a == 0) {
      return child;
    }

    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _ScanlinePainter(tint)),
          ),
        ),
      ],
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  _ScanlinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => old.color != color;
}
