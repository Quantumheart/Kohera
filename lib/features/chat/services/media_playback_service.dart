import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:kohera/core/media/kohera_player.dart';

// coverage:ignore-start

// ── Single-active-player enforcement ──────────────────────────

class MediaPlaybackService extends ChangeNotifier {
  String? _activeEventId;
  KoheraPlayer? _activePlayer;

  String? get activeEventId => _activeEventId;

  void registerPlayer(String eventId, KoheraPlayer player) {
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

  // notifyListeners() may be invoked from a State.dispose() callback, which
  // runs while the widget tree is locked (build/layout/paint phase). Deferring
  // to the next frame avoids the "widget tree was locked" assertion.
  void _notify() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => notifyListeners());
    } else {
      notifyListeners();
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
