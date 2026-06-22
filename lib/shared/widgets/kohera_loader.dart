import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated brand loader: the mycelial mark stands static while a pulse of
/// light fires from the base out to a node, picking a different thread each
/// time so the network appears to signal at random.
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
    duration: const Duration(milliseconds: 900),
  )..repeat();

  final math.Random _random = math.Random();
  int _activeLeg = 0;
  double _lastValue = 0;

  @override
  void initState() {
    super.initState();
    _activeLeg = _random.nextInt(_MyceliumPulsePainter.rootCount);
    _controller.addListener(_onTick);
  }

  void _onTick() {
    if (_controller.value < _lastValue) {
      _activeLeg = _nextLeg();
    }
    _lastValue = _controller.value;
  }

  int _nextLeg() {
    if (_MyceliumPulsePainter.rootCount < 2) return 0;
    final next = _random.nextInt(_MyceliumPulsePainter.rootCount - 1);
    return next >= _activeLeg ? next + 1 : next;
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTick)
      ..dispose();
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
            painter: _MyceliumPulsePainter(
              progress: _controller.value,
              activeLeg: _activeLeg,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _MyceliumPulsePainter extends CustomPainter {
  _MyceliumPulsePainter({
    required this.progress,
    required this.activeLeg,
    required this.color,
  });

  final double progress;
  final int activeLeg;
  final Color color;

  // Roots as base→mid→tip on the same 100×100 grid as the brand mark.
  static const _roots = <List<double>>[
    [26.0, 71.0, 10.0, 92.0],
    [39.2, 68.0, 32.0, 86.0],
    [52.4, 72.0, 54.0, 94.0],
    [65.6, 67.0, 76.0, 84.0],
    [75.2, 70.0, 92.0, 90.0],
  ];

  static int get rootCount => _roots.length;

  static const _base = Offset(50, 50);

  // Light travels during the first portion of the cycle, then rests.
  static const _travel = 0.72;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100.0);

    // ── Static mark: cap, stem, source node ──
    final markPaint = Paint()
      ..color = color
      ..isAntiAlias = true;
    _drawCapStem(canvas, markPaint);
    canvas.drawCircle(_base, 5, markPaint);

    // ── Static threads + nodes ──
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final node = Paint()
      ..color = color
      ..isAntiAlias = true;

    for (final r in _roots) {
      final mid = Offset(r[0], r[1]);
      final tip = Offset(r[2], r[3]);
      canvas.drawPath(
        Path()
          ..moveTo(_base.dx, _base.dy)
          ..lineTo(mid.dx, mid.dy)
          ..lineTo(tip.dx, tip.dy),
        stroke,
      );
      canvas.drawCircle(tip, 4.5, node);
    }

    // ── Pulse of light firing along the active thread ──
    _drawPulse(canvas);
  }

  void _drawPulse(Canvas canvas) {
    final t = (progress / _travel).clamp(0.0, 1.0);
    if (t <= 0 || t >= 1) return;

    final r = _roots[activeLeg];
    final mid = Offset(r[0], r[1]);
    final tip = Offset(r[2], r[3]);
    final head = _pointAlong(mid, tip, t);

    // Quick fire-in, sustained, fade-out as it lands.
    final intensity = (t < 0.15 ? t / 0.15 : (1 - (t - 0.15) / 0.85))
        .clamp(0.0, 1.0);
    final light = Color.lerp(color, Colors.white, 0.7)!;

    // Glow trail behind the head.
    final glow = Paint()
      ..color = light.withValues(alpha: 0.55 * intensity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..isAntiAlias = true;
    for (var i = 1; i <= 4; i++) {
      final tt = (t - i * 0.06).clamp(0.0, 1.0);
      if (tt <= 0) break;
      final p = _pointAlong(mid, tip, tt);
      canvas.drawCircle(p, 3.5 - i * 0.5, glow);
    }

    // Bright core.
    canvas.drawCircle(
      head,
      4,
      Paint()
        ..color = light.withValues(alpha: intensity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2)
        ..isAntiAlias = true,
    );

    // Node flash as the light arrives.
    final arrival = ((t - 0.82) / 0.18).clamp(0.0, 1.0);
    if (arrival > 0) {
      canvas.drawCircle(
        tip,
        4.5 + 4 * arrival,
        Paint()
          ..color = light.withValues(alpha: (1 - arrival) * 0.9)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
          ..isAntiAlias = true,
      );
    }
  }

  Offset _pointAlong(Offset mid, Offset tip, double t) {
    final l1 = (mid - _base).distance;
    final l2 = (tip - mid).distance;
    final d = t * (l1 + l2);
    if (d <= l1) return Offset.lerp(_base, mid, l1 == 0 ? 0 : d / l1)!;
    return Offset.lerp(mid, tip, l2 == 0 ? 0 : (d - l1) / l2)!;
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

  @override
  bool shouldRepaint(_MyceliumPulsePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.activeLeg != activeLeg ||
      oldDelegate.color != color;
}
