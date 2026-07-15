import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kohera/core/media/kohera_media_source.dart';
import 'package:kohera/core/media/kohera_video_controller.dart';
import 'package:video_player/video_player.dart';

// ── video_player video backend (iOS/Android) ──────────────────

class MobileKoheraVideoController implements KoheraVideoController {
  MobileKoheraVideoController();

  VideoPlayerController? _vp;
  bool _loop = false;

  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _duration =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _completed =
      StreamController<bool>.broadcast();
  void Function()? _listener;
  Duration _lastPosition = Duration.zero;
  Duration _lastDuration = Duration.zero;
  bool _lastPlaying = false;
  bool _lastCompleted = false;

  @override
  Future<void> open(KoheraMediaSource source) async {
    await _vp?.dispose();
    _vp = await _makeController(source);
    await _vp!.initialize();
    _wire(_vp!);
    await _vp!.setLooping(_loop);
    await _vp!.play();
  }

  @override
  Future<void> play() async {
    await _vp?.play();
  }

  @override
  Future<void> pause() async {
    await _vp?.pause();
  }

  @override
  Future<void> stop() async {
    await _vp?.pause();
    await _vp?.seekTo(Duration.zero);
  }

  @override
  Future<void> seek(Duration position) async {
    await _vp?.seekTo(position);
  }

  @override
  Future<void> setLoop(bool loop) {
    _loop = loop;
    return _vp?.setLooping(loop) ?? Future<void>.value();
  }

  @override
  Stream<bool> get playing => _playing.stream;

  @override
  Stream<Duration> get position => _position.stream;

  @override
  Stream<Duration> get duration => _duration.stream;

  @override
  Stream<bool> get completed => _completed.stream;

  @override
  Future<void> dispose() async {
    _vp?.removeListener(_listener ?? () {});
    await _vp?.dispose();
    await _playing.close();
    await _position.close();
    await _duration.close();
    await _completed.close();
  }

  @override
  Widget buildView({Widget? controlsOverlay}) {
    final vp = _vp;
    if (vp == null || !vp.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final aspectRatio = vp.value.aspectRatio;
    final surface = AspectRatio(
      aspectRatio: aspectRatio,
      child: VideoPlayer(vp),
    );
    if (controlsOverlay != null) {
      return Stack(
        alignment: Alignment.center,
        children: [ Positioned.fill(child: surface), controlsOverlay ],
      );
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(child: Center(child: surface)),
        _MobileFullscreenControls(controller: this),
      ],
    );
  }

  Future<VideoPlayerController> _makeController(KoheraMediaSource source) async =>
      switch (source) {
        KoheraFileSource(:final path) => VideoPlayerController.file(File(path)),
        KoheraAssetSource(:final assetPath) =>
          VideoPlayerController.asset(assetPath),
        KoheraBytesSource(:final bytes) =>
          VideoPlayerController.file(await _bytesToTempFile(bytes)),
      };

  Future<File> _bytesToTempFile(Uint8List bytes) async {
    final dir = await Directory.systemTemp.createTemp('kohera_video_');
    final file = File('${dir.path}/media');
    await file.writeAsBytes(bytes);
    return file;
  }

  void _wire(VideoPlayerController vp) {
    _listener = () {
      if (vp.value.isInitialized) {
        if (vp.value.position != _lastPosition) {
          _lastPosition = vp.value.position;
          _position.add(vp.value.position);
        }
        if (vp.value.duration != _lastDuration && vp.value.duration > Duration.zero) {
          _lastDuration = vp.value.duration;
          _duration.add(vp.value.duration);
        }
      }
      if (vp.value.isPlaying != _lastPlaying) {
        _lastPlaying = vp.value.isPlaying;
        _playing.add(vp.value.isPlaying);
      }
      if (vp.value.isCompleted != _lastCompleted) {
        _lastCompleted = vp.value.isCompleted;
        if (vp.value.isCompleted) _completed.add(true);
      }
    };
    vp.addListener(_listener!);
  }
}

// ── Minimal fullscreen controls for mobile video ──────────────

class _MobileFullscreenControls extends StatefulWidget {
  const _MobileFullscreenControls({required this.controller});
  final MobileKoheraVideoController controller;

  @override
  State<_MobileFullscreenControls> createState() =>
      _MobileFullscreenControlsState();
}

class _MobileFullscreenControlsState extends State<_MobileFullscreenControls> {
  late final StreamSubscription<dynamic> _playingSub;
  late final StreamSubscription<dynamic> _positionSub;
  late final StreamSubscription<dynamic> _durationSub;
  late final StreamSubscription<dynamic> _completedSub;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _barVisible = true;

  @override
  void initState() {
    super.initState();
    _playingSub = widget.controller.playing.listen((p) {
      if (mounted) setState(() => _isPlaying = p);
    });
    _positionSub = widget.controller.position.listen((p) {
      if (mounted) setState(() => _position = p);
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _barVisible = !_barVisible);
        if (_isPlaying) {
          unawaited(widget.controller.pause());
        } else {
          unawaited(widget.controller.play());
        }
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!_isPlaying)
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(12),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          if (_barVisible && _duration > Duration.zero)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Slider(
                value: _position.inMilliseconds
                    .clamp(0, _duration.inMilliseconds)
                    .toDouble(),
                max: _duration.inMilliseconds.toDouble(),
                onChanged: (v) =>
                    unawaited(widget.controller.seek(Duration(milliseconds: v.toInt()))),
              ),
            ),
        ],
      ),
    );
  }
}
