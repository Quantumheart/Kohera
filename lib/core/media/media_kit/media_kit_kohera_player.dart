import 'dart:async';

import 'package:kohera/core/media/kohera_media_source.dart';
import 'package:kohera/core/media/kohera_player.dart';
import 'package:media_kit/media_kit.dart';

// ── media_kit player backend (desktop) ────────────────────────

class MediaKitKoheraPlayer implements KoheraPlayer {
  MediaKitKoheraPlayer() : _player = Player();

  final Player _player;
  bool _loop = false;

  Player get inner => _player;

  @override
  Future<void> open(KoheraMediaSource source) async {
    await _player.open(await _toMedia(source));
    await _player.setPlaylistMode(
      _loop ? PlaylistMode.loop : PlaylistMode.none,
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
    return _player.setPlaylistMode(loop ? PlaylistMode.loop : PlaylistMode.none);
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

  Future<Media> _toMedia(KoheraMediaSource source) async => switch (source) {
        KoheraFileSource(:final path) => Media(path),
        KoheraBytesSource(:final bytes) => Media.memory(bytes),
        KoheraAssetSource(:final assetPath) => Media('asset:///$assetPath'),
      };
}
