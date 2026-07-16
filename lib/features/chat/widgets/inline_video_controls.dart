import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/media/kohera_video_controller.dart';
import 'package:kohera/core/utils/format_duration.dart';

// ── Inline video overlay controls (seek + time + play/pause) ───
//
// Rendered as the `controlsOverlay` of a `KoheraVideoController` surface inside
// `VideoBubble`. Display values (playing/position/duration) are pushed in from
// the bubble's stream subscriptions; this widget owns only scrub gesture state.

class InlineVideoControls extends StatefulWidget {
  const InlineVideoControls({
    required this.controller,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.onOpenFullscreen,
    super.key,
  });

  final KoheraVideoController controller;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final VoidCallback onOpenFullscreen;

  @override
  State<InlineVideoControls> createState() => _InlineVideoControlsState();
}

class _InlineVideoControlsState extends State<InlineVideoControls> {
  bool _scrubbing = false;
  bool _scrubWasPlaying = false;
  Duration _scrubPosition = Duration.zero;

  Duration get _displayPosition =>
      _scrubbing ? _scrubPosition : widget.position;

  double get _progressFraction {
    final total = widget.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (_displayPosition.inMilliseconds / total).clamp(0.0, 1.0);
  }

  void _togglePlayPause() {
    if (widget.isPlaying) {
      unawaited(widget.controller.pause());
    } else {
      unawaited(widget.controller.play());
    }
  }

  void _seekFromDx(double dx, BuildContext barContext) {
    if (widget.duration == Duration.zero) return;
    final box = barContext.findRenderObject()! as RenderBox;
    final width = box.size.width;
    if (width <= 0) return;
    final fraction = (dx / width).clamp(0.0, 1.0);
    final target = Duration(
      milliseconds: (fraction * widget.duration.inMilliseconds).round(),
    );
    setState(() => _scrubPosition = target);
    unawaited(widget.controller.seek(target));
  }

  void _onScrubStart(double dx, BuildContext barContext) {
    _scrubWasPlaying = widget.isPlaying;
    _scrubbing = true;
    if (_scrubWasPlaying) unawaited(widget.controller.pause());
    _seekFromDx(dx, barContext);
  }

  void _onScrubEnd() {
    _scrubbing = false;
    if (_scrubWasPlaying) unawaited(widget.controller.play());
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.expand(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePlayPause,
          ),
        ),
        if (!widget.isPlaying)
          IconButton(
            key: const ValueKey('videoInlinePlayButton'),
            icon: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 32,
            ),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.4),
            ),
            onPressed: _togglePlayPause,
          ),
        Positioned(
          top: 6,
          right: 6,
          child: IconButton.filled(
            onPressed: widget.onOpenFullscreen,
            icon: const Icon(Icons.fullscreen_rounded, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.5),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(4),
              minimumSize: const Size(32, 32),
            ),
          ),
        ),
        Positioned(
          left: 6,
          right: 6,
          bottom: 6,
          child: _buildScrubBar(),
        ),
      ],
    );
  }

  Widget _buildScrubBar() {
    final fraction = _progressFraction;
    return Row(
      children: [
        _timeLabel(formatDuration(_displayPosition)),
        const SizedBox(width: 6),
        Expanded(
          child: Builder(
            builder: (barContext) {
              void seekFromDx(double dx) => _seekFromDx(dx, barContext);

              return GestureDetector(
                key: const ValueKey('videoScrubBar'),
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => seekFromDx(d.localPosition.dx),
                onHorizontalDragStart: (d) =>
                    _onScrubStart(d.localPosition.dx, barContext),
                onHorizontalDragUpdate: (d) => seekFromDx(d.localPosition.dx),
                onHorizontalDragEnd: (_) => _onScrubEnd(),
                child: CustomPaint(
                  size: const Size(double.infinity, 6),
                  painter: _ProgressBarPainter(
                    progress: fraction,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 6),
        _timeLabel(formatDuration(widget.duration)),
      ],
    );
  }

  Widget _timeLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

// ── Inline progress bar painter ───────────────────────────────

class _ProgressBarPainter extends CustomPainter {
  _ProgressBarPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    final track = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Radius.zero,
      ),
      track,
    );
    final filledWidth =
        (size.width * progress.clamp(0.0, 1.0)).clamp(0.0, size.width);
    final fill = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, filledWidth, size.height),
        Radius.zero,
      ),
      fill,
    );
  }

  @override
  bool shouldRepaint(_ProgressBarPainter old) =>
      old.progress != progress ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor;
}
