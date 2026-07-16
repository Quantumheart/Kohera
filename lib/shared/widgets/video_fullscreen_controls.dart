import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/media/kohera_video_controller.dart';
import 'package:kohera/core/utils/format_duration.dart';

// ── Shared fullscreen video controls (mobile + desktop) ──────
//
// Backend-agnostic control layer over a `KoheraVideoController` video
// surface. Both the mobile (`video_player`) and desktop (`media_kit`)
// backends render this same widget in fullscreen via
// `buildView(controlsOverlay:)`.
//
// Tap anywhere on the surface toggles play/pause. The slider sits above the
// tap layer so seeking never toggles playback. Swipe-to-dismiss is handled by
// `MediaViewerShell`.

class VideoFullscreenControls extends StatefulWidget {
  const VideoFullscreenControls({
    required this.controller,
    this.initialIsPlaying = false,
    this.initialPosition = Duration.zero,
    this.initialDuration = Duration.zero,
    super.key,
  });

  final KoheraVideoController controller;
  final bool initialIsPlaying;
  final Duration initialPosition;
  final Duration initialDuration;

  @override
  State<VideoFullscreenControls> createState() =>
      _VideoFullscreenControlsState();
}

class _VideoFullscreenControlsState extends State<VideoFullscreenControls> {
  late final StreamSubscription<dynamic> _playingSub;
  late final StreamSubscription<dynamic> _positionSub;
  late final StreamSubscription<dynamic> _durationSub;
  late final StreamSubscription<dynamic> _completedSub;
  late bool _isPlaying;
  late Duration _position;
  late Duration _duration;
  bool _scrubbing = false;
  bool _scrubWasPlaying = false;

  @override
  void initState() {
    super.initState();
    _isPlaying = widget.initialIsPlaying;
    _position = widget.initialPosition;
    _duration = widget.initialDuration;
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

  void _togglePlayback() {
    if (_isPlaying) {
      unawaited(widget.controller.pause());
    } else {
      unawaited(widget.controller.play());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePlayback,
            child: Align(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    _isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_duration > Duration.zero)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  _timeLabel(formatDuration(_position)),
                  Expanded(
                    child: Slider(
                      value: _position.inMilliseconds
                          .clamp(0, _duration.inMilliseconds)
                          .toDouble(),
                      max: _duration.inMilliseconds.toDouble(),
                      onChangeStart: (_) {
                        setState(() => _scrubbing = true);
                        _scrubWasPlaying = _isPlaying;
                        if (_scrubWasPlaying) {
                          unawaited(widget.controller.pause());
                        }
                      },
                      onChanged: (v) => setState(
                        () => _position = Duration(milliseconds: v.toInt()),
                      ),
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
                  _timeLabel(formatDuration(_duration)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _timeLabel(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
