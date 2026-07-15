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
  File? _tempFile;

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
    _disposeCurrent();
    final made = await _makeController(source);
    _vp = made.controller;
    _tempFile = made.tempFile;
    await _vp!.initialize();
    _wire(_vp!);
    await _vp!.setLooping(_loop);
    await _vp!.play();
  }

  @override
  Future<void> play() async {
    if (_vp?.value.isCompleted == true) {
      await _vp!.seekTo(Duration.zero);
    }
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
    _disposeCurrent();
    await _playing.close();
    await _position.close();
    await _duration.close();
    await _completed.close();
  }

  void _disposeCurrent() {
    final vp = _vp;
    final listener = _listener;
    if (vp != null && listener != null) vp.removeListener(listener);
    unawaited(vp?.dispose());
    _vp = null;
    _listener = null;
    final temp = _tempFile;
    _tempFile = null;
    if (temp != null) unawaited(_deleteQuietly(temp));
  }

  Future<void> _deleteQuietly(File f) async {
    try {
      await f.delete();
    } catch (_) {}
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

  Future<({VideoPlayerController controller, File? tempFile})>
      _makeController(KoheraMediaSource source) async {
    switch (source) {
      case KoheraFileSource(:final path):
        return (
          controller: VideoPlayerController.file(File(path)),
          tempFile: null,
        );
      case KoheraAssetSource(:final assetPath):
        return (
          controller: VideoPlayerController.asset(assetPath),
          tempFile: null,
        );
      case KoheraBytesSource(:final bytes):
        final file = await _bytesToTempFile(bytes);
        return (
          controller: VideoPlayerController.file(file),
          tempFile: file,
        );
    }
  }

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
