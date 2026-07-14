import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:kohera/core/media/media_player.dart';

// coverage:ignore-start

// ── Single-active-player enforcement ──────────────────────────

class MediaPlaybackService extends ChangeNotifier {
  String? _activeEventId;
  MediaPlayer? _activePlayer;

  String? get activeEventId => _activeEventId;

  void registerPlayer(String eventId, MediaPlayer player) {
    if (_activeEventId != null && _activeEventId != eventId) {
      unawaited(_activePlayer?.pause());
    }
    _activeEventId = eventId;
    _activePlayer = player;
    _notify();
  }

  void unregisterPlayer(String eventId) {
    if (_activeEventId == eventId) {
      _activeEventId = null;
      _activePlayer = null;
      _notify();
    }
  }

  void pauseActive() {
    unawaited(_activePlayer?.pause());
  }

  // Player callbacks (init/dispose) can resume mid-frame when using
  // video_player/just_audio (unlike the slower media_kit init). Deferring
  // the notification avoids "widget tree was locked" crashes.
  void _notify() {
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.idle) {
      notifyListeners();
    } else {
      binding.addPostFrameCallback((_) => notifyListeners());
    }
  }

  @override
  void dispose() {
    unawaited(_activePlayer?.pause());
    _activePlayer = null;
    _activeEventId = null;
    super.dispose();
  }
}
// coverage:ignore-end
