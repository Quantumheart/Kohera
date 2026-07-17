import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated brand loader: the pixelated mycelial mushroom stands static while
/// a spark of light travels from the cap down the stem and out along one
/// thread to its node (a different thread each cycle, so the network appears
/// to signal at random), and pale spores are released from the gills under the
/// cap and fall downward, dispersing before the mycelial fan. The mushroom +
/// spark follow [color] (default the theme primary); gills are a darker primary,
/// spores a lighter primary — all from the active theme. See
/// `plans/brand_colorized_mark_brief.md`.
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
    final cs = Theme.of(context).colorScheme;
    final color = widget.color ?? cs.primary;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, _) => CustomPaint(
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

/// A thread from the stem foot out to a node. [fire] is the full synapse path
/// the spark travels — from the cap top, down the stem to this thread's origin,
/// then out along the thread to its node.
class _Leg {
  factory _Leg(List<_Cubic> segments, Offset tip) {
    final origin = segments.first.p0;
    final fire = <_Cubic>[
      _Cubic(_capSource, const Offset(50, 31), const Offset(52, 45), origin),
      ...segments,
    ];
    final lens = fire.map(_cubicLength).toList();
    final total = lens.fold<double>(0, (a, b) => a + b);
    return _Leg._(fire, tip, lens, total);
  }

  _Leg._(this.fire, this.tip, this._lens, this.total);

  final List<_Cubic> fire;
  final Offset tip;
  final List<double> _lens;
  final double total;
}

const int _samples = 16;
const int _grid = 32;

// ── Spore release ───────────────────────────────────────────────────────────
// The mushroom+spark is drawn in an inner box (0.70 of the tile) so spores
// released from the gills under the cap fall into the space alongside the
// stem. Six spores drift down and outward, fading before the mycelial fan
// (rows 20+), staggered so the release looks continuous. Gills are short ticks
// under the cap rim (rows 9-10) where the spores are born.
const double _innerScale = 0.70;
const int _sporeCount = 6;
const double _sporeSpawnGy = 9.5; // release row, just under the cap / gills
const double _sporeFall = 9;    // grid rows fallen over one spore's life
const List<double> _sporeGx = [6, 9, 11, 21, 23, 25];
const List<int> _gillGx = [7, 10, 13, 19, 22, 25];
const List<int> _gillRows = [9, 10];

// Where the spark ignites — the top edge of the mushroom cap.
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

// ── Static pixel mask (32×32): pixelated cap + stem + single centre thread and
//    four outer threads with node feet, matching assets/icons/kohera_mark.svg. ──
const List<String> _mask = [
  '................................',
  '............#####...............',
  '.........#############..........',
  '.......#################........',
  '......###################.......',
  '......####################......',
  '.....#####################......',
  '.....#####################......',
  '.....#####################......',
  '..............####..............',
  '..............#####.............',
  '..............#####.............',
  '..............#####.............',
  '...............####.............',
  '...............###..............',
  '...............###..............',
  '..............####..............',
  '..............####..............',
  '..............#####.............',
  '.............#######............',
  '............########............',
  '...........####.#.####..........',
  '..........##.#.##.#####.........',
  '.........##.##.##..#..##........',
  '........##..#...#..##..##.......',
  '......###..##..##...##..##......',
  '.....##...##...##...##...###....',
  '..####...##....##....###..####..',
  '..###...###....##....###...###..',
  '..###...###....##....###....##..',
  '..............####..............',
  '...............##...............',
];

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
  static const _trunk =
      _Cubic(Offset(50.5, 50), Offset(50.5, 58), Offset(51, 65), _fork);

  static final List<_Leg> _legs = <_Leg>[
    _Leg(
      const [_Cubic(Offset(47.8, 50), Offset(47, 62), Offset(30, 75), Offset(11, 89))],
      const Offset(11, 89),
    ),
    _Leg(
      const [_Cubic(Offset(49.15, 50), Offset(48.5, 63), Offset(37, 80), Offset(30, 90))],
      const Offset(30, 90),
    ),
    _Leg(
      const [
        _trunk,
        _Cubic(_fork, Offset(50.5, 80), Offset(50, 88), Offset(50, 96)),
      ],
      const Offset(50, 96),
    ),
    _Leg(
      const [_Cubic(Offset(51.85, 50), Offset(52.5, 63), Offset(64, 78), Offset(71, 90))],
      const Offset(71, 90),
    ),
    _Leg(
      const [_Cubic(Offset(53.2, 50), Offset(54, 62), Offset(72, 74), Offset(90, 89))],
      const Offset(90, 89),
    ),
  ];

  static int get legCount => _legs.length;

  // Light travels during the first portion of the cycle, then rests.
  static const _travel = 0.72;
  static const _trail = 5;

  @override
  void paint(Canvas canvas, Size size) {
    // ── Mushroom + gills + spark in the inner box (spores fall beside the stem) ──
    final inner = size.width * _innerScale;
    final off = (size.width - inner) / 2;
    canvas.save();
    canvas.translate(off, off);
    canvas.scale(inner / _grid);

    final markPaint = Paint()..color = color;
    for (var y = 0; y < _grid; y++) {
      final row = _mask[y];
      for (var x = 0; x < _grid; x++) {
        if (row.codeUnitAt(x) == 0x23) {
          canvas.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1), markPaint);
        }
      }
    }
    _drawGills(canvas);
    _drawPulse(canvas);
    _drawSpores(canvas);
    canvas.restore();
  }

  void _drawGills(Canvas canvas) {
    // Short ticks hanging under the cap rim, beside the stem — the spore-
    // bearing surface. Darker primary so they read as gill shadow.
    final gillColor = Color.lerp(color, Colors.black, 0.35)!;
    final paint = Paint()..color = gillColor;
    for (final gx in _gillGx) {
      for (final gy in _gillRows) {
        canvas.drawRect(Rect.fromLTWH(gx.toDouble(), gy.toDouble(), 1, 1), paint);
      }
    }
  }

  void _drawSpores(Canvas canvas) {
    // Six spores released from the gills under the cap, staggered so the fall
    // is continuous. Each falls _sporeFall grid rows over its life, drifting
    // outward (outer spores more), fading in at release and out before the
    // mycelial fan. Snapped to grid rows to stay pixel-crisp.
    final sporeColor = Color.lerp(color, Colors.white, 0.5)!;
    for (var i = 0; i < _sporeCount; i++) {
      final local = (progress + i / _sporeCount) % 1.0;
      final gy = (_sporeSpawnGy + _sporeFall * local).round();
      final drift = (_sporeGx[i] - 16) * 0.18 * local;
      final gx = (_sporeGx[i] + drift).round();
      var alpha = 1.0;
      if (local < 0.12) {
        alpha = local / 0.12;
      } else if (local > 0.65) {
        alpha = ((1 - local) / 0.35).clamp(0.0, 1.0);
      }
      canvas.drawRect(
        Rect.fromLTWH(gx.toDouble(), gy.toDouble(), 1, 1),
        Paint()..color = sporeColor.withValues(alpha: alpha),
      );
    }
  }

  void _drawPulse(Canvas canvas) {
    final t = (progress / _travel).clamp(0.0, 1.0);
    if (t <= 0 || t >= 1) return;

    final leg = _legs[activeLeg];
    final light = Color.lerp(color, Colors.white, 0.9)!;
    final fade = (t < 0.12 ? t / 0.12 : 1.0).clamp(0.0, 1.0);

    // Head plus a short trail behind it, each cell a solid pixel.
    for (var i = 0; i <= _trail; i++) {
      final tt = t - i * 0.055;
      if (tt < 0) break;
      final cell = _cell(_legPoint(leg, tt));
      final c = Color.lerp(light, color, i / _trail)!;
      canvas.drawRect(
        Rect.fromLTWH(cell.dx, cell.dy, 1, 1),
        Paint()..color = c.withValues(alpha: fade),
      );
    }

    // Node flash as the spark lands.
    final arrival = ((t - 0.82) / 0.18).clamp(0.0, 1.0);
    if (arrival > 0) {
      final tip = _cell(leg.tip);
      final flash = Paint()
        ..color = light.withValues(alpha: 1 - arrival);
      for (final d in const [Offset.zero, Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)]) {
        canvas.drawRect(
          Rect.fromLTWH(tip.dx + d.dx, tip.dy + d.dy, 1, 1),
          flash,
        );
      }
    }
  }

  // Map a point on the 100×100 brand grid to a snapped 32×32 pixel cell.
  Offset _cell(Offset p) => Offset(
        (p.dx * _grid / 100).floor().clamp(0, _grid - 1).toDouble(),
        (p.dy * _grid / 100).floor().clamp(0, _grid - 1).toDouble(),
      );

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

  @override
  bool shouldRepaint(_MyceliumPulsePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.activeLeg != activeLeg ||
      oldDelegate.color != color;
}
