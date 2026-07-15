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
    if (controlsOverlay == null) {
      return Center(child: surface);
    }
    return Stack(
      alignment: Alignment.center,
      children: [ Positioned.fill(child: surface), controlsOverlay ],
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
