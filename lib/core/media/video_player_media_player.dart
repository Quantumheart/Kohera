import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:kohera/core/media/resolved_media.dart';
import 'package:kohera/core/media/video_media_player.dart';
import 'package:video_player/video_player.dart';

// ── video_player implementation (Android + iOS) ───────────────

class VideoPlayerMediaPlayer implements VideoMediaPlayer {
  VideoPlayerMediaPlayer();

  VideoPlayerController? _controller;

  final _playingController = StreamController<bool>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _completedController = StreamController<bool>.broadcast();

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  Stream<bool> get onPlayingChanged => _playingController.stream;
  @override
  Stream<Duration> get onPositionChanged => _positionController.stream;
  @override
  Stream<Duration> get onDurationChanged => _durationController.stream;
  @override
  Stream<bool> get onCompleted => _completedController.stream;

  @override
  bool get isPlaying => _isPlaying;
  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  @override
  bool get canSeek => true;

  @override
  Future<void> open(ResolvedMedia media) async {
    await _controller?.dispose();
    _controller = VideoPlayerController.file(File(media.filePath!));
    await _controller!.initialize();
    _controller!.addListener(_onValueChanged);
    _duration = _controller!.value.duration;
    _durationController.add(_duration);
  }

  @override
  Future<void> openAsset(String assetPath) async {
    await _controller?.dispose();
    _controller = VideoPlayerController.asset(assetPath);
    await _controller!.initialize();
    _controller!.addListener(_onValueChanged);
    _duration = _controller!.value.duration;
    _durationController.add(_duration);
  }

  void _onValueChanged() {
    final v = _controller!.value;
    if (v.isPlaying != _isPlaying) {
      _isPlaying = v.isPlaying;
      _playingController.add(v.isPlaying);
    }
    if (v.position != _position) {
      _position = v.position;
      _positionController.add(v.position);
    }
    if (v.duration != _duration && v.duration != Duration.zero) {
      _duration = v.duration;
      _durationController.add(v.duration);
    }
    if (v.isCompleted) {
      _completedController.add(true);
    }
  }

  @override
  Future<void> play() => _controller!.play();

  @override
  Future<void> pause() => _controller!.pause();

  @override
  Future<void> stop() async {
    await _controller!.pause();
    await _controller!.seekTo(Duration.zero);
  }

  @override
  Future<void> seek(Duration position) => _controller!.seekTo(position);

  @override
  void setLoopMode(bool loop) {
    unawaited(_controller?.setLooping(loop));
  }

  @override
  Widget buildView() {
    return VideoPlayer(_controller!);
  }

  @override
  Future<void> dispose() async {
    _controller?.removeListener(_onValueChanged);
    await _playingController.close();
    await _positionController.close();
    await _durationController.close();
    await _completedController.close();
    await _controller?.dispose();
    _controller = null;
  }
}
