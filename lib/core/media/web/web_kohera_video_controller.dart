import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kohera/core/media/kohera_media_source.dart';
import 'package:kohera/core/media/kohera_video_controller.dart';
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

// ── video_player video backend (web) ──────────────────────────
//
// Uses the video_player HTML5 <video> backend. Decrypted bytes are exposed
// via a blob: object URL so the element can stream them without a temp file.

class WebKoheraVideoController implements KoheraVideoController {
  WebKoheraVideoController();

  VideoPlayerController? _vp;
  bool _loop = false;
  String? _blobUrl;

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
    _vp = await _makeController(source);
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
    _revokeBlobUrl();
  }

  void _revokeBlobUrl() {
    final url = _blobUrl;
    _blobUrl = null;
    if (url != null) {
      try {
        web.URL.revokeObjectURL(url);
      } catch (_) {}
    }
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
      children: [Positioned.fill(child: surface), controlsOverlay],
    );
  }

  Future<VideoPlayerController> _makeController(KoheraMediaSource source) async {
    switch (source) {
      case KoheraBytesSource(:final bytes, :final mimeType):
        final url = _bytesToBlobUrl(bytes, mimeType);
        return VideoPlayerController.networkUrl(Uri.parse(url));
      case KoheraAssetSource(:final assetPath):
        return VideoPlayerController.asset(assetPath);
      case KoheraFileSource(:final path):
        return VideoPlayerController.networkUrl(Uri.parse(path));
    }
  }

  String _bytesToBlobUrl(Uint8List bytes, String? mimeType) {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType ?? 'video/mp4'),
    );
    _blobUrl = web.URL.createObjectURL(blob);
    return _blobUrl!;
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
