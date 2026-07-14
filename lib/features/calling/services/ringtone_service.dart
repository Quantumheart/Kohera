import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kohera/core/media/media_player.dart';
import 'package:kohera/core/media/media_player_factory.dart';

// coverage:ignore-start
class RingtoneService {
  MediaPlayer? _player;

  MediaPlayer _ensurePlayer() => _player ??= MediaPlayerFactory.createAudio();

  Future<void> playRingtone({bool loop = true}) async {
    await stop();
    final player = _ensurePlayer();
    await player.openAsset('assets/audio/ringtone.mp3');
    if (loop) player.setLoopMode(true);
    await player.play();
    if (!kIsWeb) unawaited(HapticFeedback.mediumImpact().catchError((_) {}));
  }

  Future<void> playDialtone({bool loop = true}) async {
    await stop();
    final player = _ensurePlayer();
    await player.openAsset('assets/audio/dialtone.mp3');
    if (loop) player.setLoopMode(true);
    await player.play();
  }

  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }

  // ── PTT sounds ──────────────────────────────────────────────

  MediaPlayer? _pttPlayer;

  MediaPlayer _ensurePttPlayer() =>
      _pttPlayer ??= MediaPlayerFactory.createAudio();

  Future<void> playPTTOn() async {
    await _ensurePttPlayer().openAsset('assets/audio/ptt_on.mp3');
    unawaited(_pttPlayer?.play());
  }

  Future<void> playPTTOff() async {
    await _ensurePttPlayer().openAsset('assets/audio/ptt_off.mp3');
    unawaited(_pttPlayer?.play());
  }

  // ── Participant join/leave sounds ──────────────────────────

  final List<MediaPlayer?> _participantPlayers = [null, null];
  int _participantPlayerIndex = 0;

  MediaPlayer _nextParticipantPlayer() {
    final idx = _participantPlayerIndex;
    _participantPlayerIndex = (idx + 1) % _participantPlayers.length;
    return _participantPlayers[idx] ??= MediaPlayerFactory.createAudio();
  }

  Future<void> playUserJoined() async {
    try {
      final player = _nextParticipantPlayer();
      await player.openAsset('assets/audio/user_join.mp3');
      unawaited(player.play());
    } catch (e) {
      debugPrint('[Kohera] playUserJoined failed: $e');
    }
  }

  Future<void> playUserLeft() async {
    try {
      final player = _nextParticipantPlayer();
      await player.openAsset('assets/audio/user_leave.mp3');
      unawaited(player.play());
    } catch (e) {
      debugPrint('[Kohera] playUserLeft failed: $e');
    }
  }

  Future<void> dispose() async {
    await stop();
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
    try {
      await _pttPlayer?.dispose();
    } catch (_) {}
    _pttPlayer = null;
    for (var i = 0; i < _participantPlayers.length; i++) {
      try {
        await _participantPlayers[i]?.dispose();
      } catch (_) {}
      _participantPlayers[i] = null;
    }
  }
}
// coverage:ignore-end
