import 'dart:math' as math;
import 'dart:ui' as ui;

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
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  final math.Random _random = math.Random();
  int _activeLeg = 0;
  double _lastValue = 0;

  @override
  void initState() {
    super.initState();
    _activeLeg = _random.nextInt(_MyceliumPulsePainter.legCount);
    _controller.addListener(_onTick);
  }

  void _onTick() {
    if (_controller.value < _lastValue) {
      _activeLeg = _nextLeg();
    }
    _lastValue = _controller.value;
  }

  int _nextLeg() {
    if (_MyceliumPulsePainter.legCount < 2) return 0;
    final next = _random.nextInt(_MyceliumPulsePainter.legCount - 1);
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

/// A single cubic Bézier segment on the 100×100 brand grid.
class _Cubic {
  const _Cubic(this.p0, this.p1, this.p2, this.p3);
  final Offset p0;
  final Offset p1;
  final Offset p2;
  final Offset p3;
}

/// A thread from the base out to a node, made of one or more curved segments.
/// Threads that share a leading segment read as a fork in the network.
///
/// [segments] is the static thread (origin → tip) that gets drawn. [fire] is
/// the longer synapse path the pulse travels — from inside the cap, down the
/// stem to this thread's origin, then out along the thread to its node.
class _Leg {
  factory _Leg(List<_Cubic> segments, Offset tip, double nodeRadius) {
    final origin = segments.first.p0;
    final fire = <_Cubic>[
      _Cubic(_capSource, const Offset(50, 31), const Offset(52, 45), origin),
      ...segments,
    ];
    final lens = fire.map(_cubicLength).toList();
    final total = lens.fold<double>(0, (a, b) => a + b);
    return _Leg._(segments, fire, tip, nodeRadius, lens, total);
  }

  _Leg._(
    this.segments,
    this.fire,
    this.tip,
    this.nodeRadius,
    this._lens,
    this.total,
  );

  final List<_Cubic> segments;
  final List<_Cubic> fire;
  final Offset tip;
  final double nodeRadius;
  final List<double> _lens;
  final double total;
}

const int _samples = 16;

// Where the synapse ignites — the top edge of the mushroom cap.
const Offset _capSource = Offset(50, 4);

Offset _cubicPoint(_Cubic c, double u) {
  final mu = 1 - u;
  final a = mu * mu * mu;
  final b = 3 * mu * mu * u;
  final cc = 3 * mu * u * u;
  final d = u * u * u;
  return Offset(
    a * c.p0.dx + b * c.p1.dx + cc * c.p2.dx + d * c.p3.dx,
    a * c.p0.dy + b * c.p1.dy + cc * c.p2.dy + d * c.p3.dy,
  );
}

double _cubicLength(_Cubic c) {
  var len = 0.0;
  var prev = c.p0;
  for (var i = 1; i <= _samples; i++) {
    final p = _cubicPoint(c, i / _samples);
    len += (p - prev).distance;
    prev = p;
  }
  return len;
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

  static const _fork = Offset(51, 71);

  // Thread origins are tucked inside the stem foot (centred on 50.5) so the
  // threads emerge as a bundle under the stem and splay lower down — none poke
  // past the stem edges. The fan is symmetric.
  static const _trunk =
      _Cubic(Offset(50.5, 50), Offset(50.5, 58), Offset(51, 65), _fork);

  static final List<_Leg> _legs = <_Leg>[
    _Leg(
      const [_Cubic(Offset(47.8, 50), Offset(47, 62), Offset(30, 75), Offset(11, 89))],
      const Offset(11, 89),
      4.6,
    ),
    _Leg(
      const [_Cubic(Offset(49.15, 50), Offset(48.5, 63), Offset(37, 80), Offset(30, 90))],
      const Offset(30, 90),
      4,
    ),
    _Leg(
      const [
        _trunk,
        _Cubic(_fork, Offset(50, 80), Offset(46, 88), Offset(41, 93)),
      ],
      const Offset(41, 93),
      5,
    ),
    _Leg(
      const [
        _trunk,
        _Cubic(_fork, Offset(53, 80), Offset(57, 88), Offset(61, 91)),
      ],
      const Offset(61, 91),
      4.3,
    ),
    _Leg(
      const [_Cubic(Offset(51.85, 50), Offset(52.5, 63), Offset(64, 78), Offset(71, 90))],
      const Offset(71, 90),
      4.5,
    ),
    _Leg(
      const [_Cubic(Offset(53.2, 50), Offset(54, 62), Offset(72, 74), Offset(90, 89))],
      const Offset(90, 89),
      3.9,
    ),
  ];

  static int get legCount => _legs.length;

  // Light travels during the first portion of the cycle, then rests.
  static const _travel = 0.72;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100.0);

    // ── Static mark: cap + stem ──
    final markPaint = Paint()
      ..color = color
      ..isAntiAlias = true;
    _drawCapStem(canvas, markPaint);

    // ── Static threads ──
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    for (final leg in _legs) {
      canvas.drawPath(_legPath(leg), stroke);
    }

    // ── Static nodes: fork junction, then tips ──
    canvas.drawCircle(_fork, 2.6, markPaint);
    for (final leg in _legs) {
      canvas.drawCircle(leg.tip, leg.nodeRadius, markPaint);
    }

    // ── Pulse of light firing along the active thread ──
    _drawPulse(canvas);
  }

  Path _legPath(_Leg leg) {
    final first = leg.segments.first;
    final path = Path()..moveTo(first.p0.dx, first.p0.dy);
    for (final c in leg.segments) {
      path.cubicTo(c.p1.dx, c.p1.dy, c.p2.dx, c.p2.dy, c.p3.dx, c.p3.dy);
    }
    return path;
  }

  void _drawPulse(Canvas canvas) {
    final t = (progress / _travel).clamp(0.0, 1.0);
    if (t <= 0 || t >= 1) return;

    final leg = _legs[activeLeg];
    final head = _legPoint(leg, t);

    // Quick fire-in, sustained, fade-out as it lands.
    final intensity = (t < 0.15 ? t / 0.15 : (1 - (t - 0.15) / 0.85))
        .clamp(0.0, 1.0);
    final light = Color.lerp(color, Colors.white, 0.7)!;

    // ── The light enters at the top edge of the cap and sweeps down through
    //    the cap and stem behind the head, then drains away as it reaches the
    //    threads. The lit region is everything above the head's current depth. ──
    final capLight = Color.lerp(color, Colors.white, 0.9)!;
    final hy = head.dy;
    final bodyEnv =
        (hy <= 46 ? 0.95 : 0.95 * (1 - (hy - 46) / 16)).clamp(0.0, 0.95);
    if (bodyEnv > 0) {
      final body = Path()
        ..addPath(_capPath(), Offset.zero)
        ..addPath(_stemPath(), Offset.zero);
      canvas
        ..save()
        ..clipPath(body)
        ..drawRect(
          const Rect.fromLTWH(0, 0, 100, 100),
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(0, hy - 7),
              Offset(0, hy + 3),
              [
                capLight.withValues(alpha: bodyEnv),
                capLight.withValues(alpha: 0),
              ],
            ),
        )
        ..restore();
    }

    // Glow trail behind the head, draining down toward the node.
    final glow = Paint()
      ..color = light.withValues(alpha: 0.55 * intensity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..isAntiAlias = true;
    for (var i = 1; i <= 6; i++) {
      final tt = t - i * 0.05;
      if (tt <= 0) break;
      canvas.drawCircle(_legPoint(leg, tt), 3.8 - i * 0.45, glow);
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
        leg.tip,
        leg.nodeRadius + 4 * arrival,
        Paint()
          ..color = light.withValues(alpha: (1 - arrival) * 0.9)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
          ..isAntiAlias = true,
      );
    }
  }

  Offset _legPoint(_Leg leg, double t) {
    var d = t.clamp(0.0, 1.0) * leg.total;
    for (var i = 0; i < leg.fire.length; i++) {
      final segLen = leg._lens[i];
      if (d <= segLen || i == leg.fire.length - 1) {
        return _pointAtDistance(leg.fire[i], d.clamp(0.0, segLen), segLen);
      }
      d -= segLen;
    }
    return leg.tip;
  }

  Offset _pointAtDistance(_Cubic c, double dist, double segLen) {
    if (segLen <= 0) return c.p3;
    var prev = c.p0;
    var acc = 0.0;
    for (var i = 1; i <= _samples; i++) {
      final p = _cubicPoint(c, i / _samples);
      final step = (p - prev).distance;
      if (acc + step >= dist) {
        final f = step == 0 ? 0.0 : ((dist - acc) / step).clamp(0.0, 1.0);
        return Offset.lerp(prev, p, f)!;
      }
      acc += step;
      prev = p;
    }
    return c.p3;
  }

  void _drawCapStem(Canvas canvas, Paint paint) {
    canvas.drawPath(_capPath(), paint);
    canvas.drawPath(_stemPath(), paint);
  }

  // Asymmetric cap: steeper, left-of-centre apex and a fuller right shoulder.
  Path _capPath() => Path()
    ..moveTo(17, 28)
    ..cubicTo(15, 7, 39, 3, 51, 5)
    ..cubicTo(67, 7, 86, 12, 81, 27)
    ..close();

  // Bent stem, bowing gently to the right.
  Path _stemPath() => Path()
    ..moveTo(43, 27)
    ..cubicTo(46, 36, 47, 44, 46, 50)
    ..lineTo(55, 50)
    ..cubicTo(59, 44, 58, 36, 56, 27)
    ..close();

  @override
  bool shouldRepaint(_MyceliumPulsePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.activeLeg != activeLeg ||
      oldDelegate.color != color;
}
