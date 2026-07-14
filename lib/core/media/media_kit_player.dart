import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kohera/core/media/resolved_media.dart';
import 'package:kohera/core/media/video_media_player.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// ── media_kit implementation (desktop + web) ──────────────────

class MediaKitPlayer implements VideoMediaPlayer {
  MediaKitPlayer();

  Player? _player;
  VideoController? _videoController;

  Player get _p {
    if (_player != null) return _player!;
    final p = Player();
    _player = p;
    _listen(p);
    return p;
  }

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
    final Media m;
    if (media.bytes != null) {
      m = await Media.memory(media.bytes!);
    } else {
      m = Media(media.filePath!);
    }
    await _p.open(m);
  }

  @override
  Future<void> openAsset(String assetPath) async {
    await _p.open(Media('asset:///$assetPath'));
  }

  @override
  Future<void> play() => _p.play();

  @override
  Future<void> pause() => _p.pause();

  @override
  Future<void> stop() => _p.stop();

  @override
  Future<void> seek(Duration position) => _p.seek(position);

  @override
  void setLoopMode(bool loop) {
    unawaited(
      _p.setPlaylistMode(loop ? PlaylistMode.loop : PlaylistMode.none),
    );
  }

  @override
  Widget buildView() {
    _videoController ??= VideoController(_p);
    return Video(controller: _videoController!);
  }

  void _listen(Player player) {
    player.stream.playing.listen((p) {
      _isPlaying = p;
      _playingController.add(p);
    });
    player.stream.position.listen((p) {
      _position = p;
      _positionController.add(p);
    });
    player.stream.duration.listen((d) {
      _duration = d;
      _durationController.add(d);
    });
    player.stream.completed.listen(_completedController.add);
  }

  @override
  Future<void> dispose() async {
    await _playingController.close();
    await _positionController.close();
    await _durationController.close();
    await _completedController.close();
    await _player?.dispose();
  }
}
