import 'dart:async';

import 'package:kohera/core/media/resolved_media.dart';

// ── Platform-agnostic media player interface ──────────────────

abstract class MediaPlayer {
  Stream<bool> get onPlayingChanged;
  Stream<Duration> get onPositionChanged;
  Stream<Duration> get onDurationChanged;
  Stream<bool> get onCompleted;

  bool get isPlaying;
  Duration get position;
  Duration get duration;
  bool get canSeek;

  Future<void> open(ResolvedMedia media);
  Future<void> openAsset(String assetPath);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  void setLoopMode(bool loop);
  Future<void> dispose();
}
