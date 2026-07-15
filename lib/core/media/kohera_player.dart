import 'dart:async';

import 'package:kohera/core/media/kohera_media_source.dart';

// ── Platform-agnostic player interface ────────────────────────
//
// Desktop (Linux/macOS/Windows) is backed by media_kit; iOS/Android is
// backed by just_audio (audio/ringtone) or video_player (video). Call sites
// depend only on this interface, never on a backend package.

abstract class KoheraPlayer {
  Future<void> open(KoheraMediaSource source);

  Future<void> play();

  Future<void> pause();

  Future<void> stop();

  Future<void> seek(Duration position);

  Future<void> setLoop(bool loop);

  Stream<bool> get playing;

  Stream<Duration> get position;

  Stream<Duration> get duration;

  Stream<bool> get completed;

  Future<void> dispose();
}
