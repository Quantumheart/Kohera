import 'dart:math' as math;

import 'package:flutter/material.dart';

class AppLogoHeader extends StatelessWidget {
  const AppLogoHeader({required this.subtitle, super.key});
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Logo ──
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: SizedBox(
              width: 42,
              height: 42,
              child: CustomPaint(
                painter: _KoheraMarkPainter(
                  markColor: cs.onPrimaryContainer,
                  nodeColor: cs.primary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Kohera', style: tt.displayLarge),
        const SizedBox(height: 4),
        Text(subtitle, style: tt.bodyMedium),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _KoheraMarkPainter extends CustomPainter {
  const _KoheraMarkPainter({required this.markColor, required this.nodeColor});

  final Color markColor;
  final Color nodeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    final mark = Paint()
      ..color = markColor
      ..isAntiAlias = true;

    // ── Cap + stem (the fruiting body) ──
    final capW = w * 0.60;
    final capH = h * 0.20;
    final capTop = h * 0.06;
    final capRect = Rect.fromLTWH(cx - capW / 2, capTop, capW, 2 * capH);
    canvas.drawPath(Path()..addArc(capRect, math.pi, math.pi)..close(), mark);

    final gill = capTop + capH;
    final baseY = h * 0.50;
    final stem = Path()
      ..moveTo(cx - w * 0.075, gill)
      ..lineTo(cx + w * 0.075, gill)
      ..lineTo(cx + w * 0.085, baseY)
      ..lineTo(cx - w * 0.085, baseY)
      ..close();
    canvas.drawPath(stem, mark);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, baseY), width: w * 0.17, height: w * 0.17 * 0.7),
      mark,
    );

    // ── Mycelial roots (the hidden network) ──
    final threads = Paint()
      ..color = markColor
      ..strokeWidth = w * 0.05
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final nodes = Paint()
      ..color = nodeColor
      ..isAntiAlias = true;

    const tips = [
      [-0.40, 0.92], [-0.18, 0.86], [0.04, 0.94], [0.26, 0.84], [0.42, 0.90],
    ];
    for (final t in tips) {
      final ex = w * (0.5 + t[0]);
      final ey = h * t[1];
      final mx = (cx + ex) / 2 + w * t[0] * 0.10;
      final my = (baseY + ey) / 2;
      canvas.drawLine(Offset(cx, baseY), Offset(mx, my), threads);
      canvas.drawLine(Offset(mx, my), Offset(ex, ey), threads);
      canvas.drawCircle(Offset(ex, ey), w * 0.06, mark);
      canvas.drawCircle(Offset(mx, my), w * 0.035, nodes);
    }
    canvas.drawCircle(Offset(cx, baseY), w * 0.07, nodes);
  }

  @override
  bool shouldRepaint(_KoheraMarkPainter oldDelegate) =>
      oldDelegate.markColor != markColor || oldDelegate.nodeColor != nodeColor;
}
