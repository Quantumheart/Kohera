import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/media/kohera_video_controller.dart';

// ── Shared fullscreen video controls (mobile + desktop) ──────
//
// Backend-agnostic control bar layered over a `KoheraVideoController` video
// surface. Both the mobile (`video_player`) and desktop (`media_kit`) backends
// render this same widget in fullscreen via `buildView(controlsOverlay:)`.

class VideoFullscreenControls extends StatefulWidget {
  const VideoFullscreenControls({required this.controller, super.key});

  final KoheraVideoController controller;

  @override
  State<VideoFullscreenControls> createState() =>
      _VideoFullscreenControlsState();
}

class _VideoFullscreenControlsState extends State<VideoFullscreenControls> {
  late final StreamSubscription<dynamic> _playingSub;
  late final StreamSubscription<dynamic> _positionSub;
  late final StreamSubscription<dynamic> _durationSub;
  late final StreamSubscription<dynamic> _completedSub;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _barVisible = true;
  bool _scrubbing = false;
  bool _scrubWasPlaying = false;

  @override
  void initState() {
    super.initState();
    _playingSub = widget.controller.playing.listen((p) {
      if (mounted) setState(() => _isPlaying = p);
    });
    _positionSub = widget.controller.position.listen((p) {
      if (mounted && !_scrubbing) setState(() => _position = p);
    });
    _durationSub = widget.controller.duration.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _completedSub = widget.controller.completed.listen((_) {
      if (mounted) setState(() => _isPlaying = false);
    });
  }

  @override
  void dispose() {
    unawaited(_playingSub.cancel());
    unawaited(_positionSub.cancel());
    unawaited(_durationSub.cancel());
    unawaited(_completedSub.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showBar = _barVisible && _duration > Duration.zero;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _barVisible = !_barVisible),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (showBar && _isPlaying)
            IconButton(
              icon: const Icon(Icons.pause_rounded, color: Colors.white, size: 40),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.4),
              ),
              onPressed: () => unawaited(widget.controller.pause()),
            ),
          if (!_isPlaying)
            IconButton(
              icon: const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 40),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.4),
              ),
              onPressed: () => unawaited(widget.controller.play()),
            ),
          if (showBar)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Slider(
                value: _position.inMilliseconds
                    .clamp(0, _duration.inMilliseconds)
                    .toDouble(),
                max: _duration.inMilliseconds.toDouble(),
                onChangeStart: (_) {
                  setState(() => _scrubbing = true);
                  _scrubWasPlaying = _isPlaying;
                  if (_scrubWasPlaying) unawaited(widget.controller.pause());
                },
                onChanged: (v) =>
                    setState(() => _position = Duration(milliseconds: v.toInt())),
                onChangeEnd: (v) {
                  final target = Duration(milliseconds: v.toInt());
                  setState(() => _scrubbing = false);
                  unawaited(widget.controller.seek(target).then((_) {
                    if (_scrubWasPlaying && mounted && !_scrubbing) {
                      unawaited(widget.controller.play());
                    }
                  }));
                },
              ),
            ),
        ],
      ),
    );
  }
}
