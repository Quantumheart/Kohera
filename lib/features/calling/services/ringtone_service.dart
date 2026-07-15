import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kohera/core/media/kohera_media_source.dart';
import 'package:kohera/core/media/kohera_player.dart';
import 'package:kohera/core/media/kohera_player_factory.dart';

// coverage:ignore-start
class RingtoneService {
  KoheraPlayer? _player;

  KoheraPlayer _ensurePlayer() => _player ??= createKoheraPlayer();

  Future<void> playRingtone({bool loop = true}) async {
    await stop();
    await _ensurePlayer()
        .open(const KoheraAssetSource('assets/audio/ringtone.mp3'));
    await _player!.setLoop(loop);
    if (!kIsWeb) unawaited(HapticFeedback.mediumImpact().catchError((_) {}));
  }

  Future<void> playDialtone({bool loop = true}) async {
    await stop();
    await _ensurePlayer()
        .open(const KoheraAssetSource('assets/audio/dialtone.mp3'));
    await _player!.setLoop(loop);
  }

  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }

  // ── PTT sounds ──────────────────────────────────────────────

  KoheraPlayer? _pttPlayer;

  KoheraPlayer _ensurePttPlayer() => _pttPlayer ??= createKoheraPlayer();

  Future<void> playPTTOn() async {
    await _ensurePttPlayer()
        .open(const KoheraAssetSource('assets/audio/ptt_on.mp3'));
  }

  Future<void> playPTTOff() async {
    await _ensurePttPlayer()
        .open(const KoheraAssetSource('assets/audio/ptt_off.mp3'));
  }

  // ── Participant join/leave sounds ──────────────────────────

  final List<KoheraPlayer?> _participantPlayers = [null, null];
  int _participantPlayerIndex = 0;

  KoheraPlayer _nextParticipantPlayer() {
    final idx = _participantPlayerIndex;
    _participantPlayerIndex = (idx + 1) % _participantPlayers.length;
    return _participantPlayers[idx] ??= createKoheraPlayer();
  }

  Future<void> playUserJoined() async {
    try {
      await _nextParticipantPlayer()
          .open(const KoheraAssetSource('assets/audio/user_join.mp3'));
    } catch (e) {
      debugPrint('[Kohera] playUserJoined failed: $e');
    }
  }

  Future<void> playUserLeft() async {
    try {
      await _nextParticipantPlayer()
          .open(const KoheraAssetSource('assets/audio/user_leave.mp3'));
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
