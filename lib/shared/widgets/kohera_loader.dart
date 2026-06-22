import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated brand loader: the mycelial network grows outward from the mushroom
/// base, each thread drawing to its node, then the whole mark fades and regrows.
class KoheraLoader extends StatefulWidget {
  const KoheraLoader({this.size = 48, this.color, super.key});

  final double size;
  final Color? color;

  @override
  State<KoheraLoader> createState() => _KoheraLoaderState();
}

class _KoheraLoaderState extends State<KoheraLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, __) => CustomPaint(
            painter: _MyceliumGrowthPainter(
              progress: _controller.value,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _MyceliumGrowthPainter extends CustomPainter {
  _MyceliumGrowthPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  // Roots as base→mid→tip on the same 100×100 grid as the brand mark.
  static const _roots = <List<double>>[
    [26.0, 71.0, 10.0, 92.0],
    [39.2, 68.0, 32.0, 86.0],
    [52.4, 72.0, 54.0, 94.0],
    [65.6, 67.0, 76.0, 84.0],
    [75.2, 70.0, 92.0, 90.0],
  ];

  static const _base = Offset(50, 50);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100.0);

    final v = progress;
    final grow = (v / 0.62).clamp(0.0, 1.0);
    final intro = (v / 0.12).clamp(0.0, 1.0);
    final fade = v < 0.82 ? 1.0 : (1 - (v - 0.82) / 0.18).clamp(0.0, 1.0);

    // ── Cap + stem + source node (fade and scale in) ──
    final introAlpha = (intro * fade).clamp(0.0, 1.0);
    final introPaint = Paint()
      ..color = color.withValues(alpha: introAlpha)
      ..isAntiAlias = true;
    canvas.save();
    final scale = 0.7 + 0.3 * intro;
    canvas
      ..translate(_base.dx, _base.dy)
      ..scale(scale)
      ..translate(-_base.dx, -_base.dy);
    _drawCapStem(canvas, introPaint);
    canvas.restore();
    canvas.drawCircle(_base, 5, introPaint);

    // ── Roots grow outward, nodes pop in on arrival ──
    final stroke = Paint()
      ..color = color.withValues(alpha: fade)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final node = Paint()
      ..color = color.withValues(alpha: fade)
      ..isAntiAlias = true;

    for (var i = 0; i < _roots.length; i++) {
      final r = _roots[i];
      final mid = Offset(r[0], r[1]);
      final tip = Offset(r[2], r[3]);
      final f = ((grow - i * 0.10) / 0.55).clamp(0.0, 1.0);
      if (f <= 0) continue;
      _drawPartialRoot(canvas, mid, tip, f, stroke);
      final pop = ((f - 0.8) / 0.2).clamp(0.0, 1.0);
      if (pop > 0) canvas.drawCircle(tip, 4.5 * pop, node);
    }
  }

  void _drawCapStem(Canvas canvas, Paint paint) {
    canvas.drawPath(
      Path()..addArc(const Rect.fromLTWH(20, 6, 60, 40), math.pi, math.pi)..close(),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(42.5, 26)
        ..lineTo(57.5, 26)
        ..lineTo(58.5, 50)
        ..lineTo(41.5, 50)
        ..close(),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: _base, width: 17, height: 17 * 0.7),
      paint,
    );
  }

  void _drawPartialRoot(
      Canvas canvas, Offset mid, Offset tip, double f, Paint stroke,) {
    final l1 = (mid - _base).distance;
    final l2 = (tip - mid).distance;
    final target = f * (l1 + l2);
    final path = Path()..moveTo(_base.dx, _base.dy);
    if (target <= l1) {
      final p = Offset.lerp(_base, mid, target / l1)!;
      path.lineTo(p.dx, p.dy);
    } else {
      path.lineTo(mid.dx, mid.dy);
      final p = Offset.lerp(mid, tip, ((target - l1) / l2).clamp(0.0, 1.0))!;
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_MyceliumGrowthPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
