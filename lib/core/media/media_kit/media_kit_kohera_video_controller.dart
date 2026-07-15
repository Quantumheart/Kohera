import 'package:flutter/material.dart';
import 'package:kohera/core/media/kohera_media_source.dart';
import 'package:kohera/core/media/kohera_video_controller.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// ── media_kit video backend (desktop) ─────────────────────────

class MediaKitKoheraVideoController implements KoheraVideoController {
  MediaKitKoheraVideoController() : _player = Player();

  final Player _player;
  late final VideoController _controller = VideoController(_player);
  bool _loop = false;

  @override
  Future<void> open(KoheraMediaSource source) async {
    await _player.open(await _toMedia(source));
    await _player.setPlaylistMode(
      _loop ? PlaylistMode.loop : PlaylistMode.single,
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setLoop(bool loop) {
    _loop = loop;
    return _player.setPlaylistMode(loop ? PlaylistMode.loop : PlaylistMode.single);
  }

  @override
  Stream<bool> get playing => _player.stream.playing;

  @override
  Stream<Duration> get position => _player.stream.position;

  @override
  Stream<Duration> get duration => _player.stream.duration;

  @override
  Stream<bool> get completed => _player.stream.completed;

  @override
  Future<void> dispose() => _player.dispose();

  @override
  Widget buildView({Widget? controlsOverlay}) {
    return Video(
      controller: _controller,
      controls: controlsOverlay == null ? null : (_) => controlsOverlay,
    );
  }

  Future<Media> _toMedia(KoheraMediaSource source) async => switch (source) {
        KoheraFileSource(:final path) => Media(path),
        KoheraBytesSource(:final bytes) => Media.memory(bytes),
        KoheraAssetSource(:final assetPath) => Media('asset:///$assetPath'),
      };
}
