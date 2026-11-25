import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:kohera/data/repositories/room_repository.dart';

/// Manages outgoing typing indicators for a single room.
///
/// Debounces `setTyping(true)` calls so the server is notified at most once
/// every [_sendInterval], and automatically stops typing after [_inactivityTimeout]
/// of silence.
class TypingController {
  TypingController({required this.roomId, required RoomRepository rooms})
      : _rooms = rooms;

  final String roomId;
  final RoomRepository _rooms;

  static const _sendInterval = Duration(seconds: 4);
  static const _inactivityTimeout = Duration(seconds: 30);

  bool _isTyping = false;
  DateTime? _lastSentAt;
  Timer? _inactivityTimer;

  /// Call when the compose text changes.
  void onTextChanged(String text) {
    if (text.isEmpty) {
      stop();
      return;
    }

    _resetInactivityTimer();

    final now = clock.now();
    if (_isTyping &&
        _lastSentAt != null &&
        now.difference(_lastSentAt!) < _sendInterval) {
      return;
    }

    _isTyping = true;
    _lastSentAt = now;
    unawaited(_sendTyping(true));
  }

  /// Stop broadcasting typing. Idempotent.
  void stop() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    if (!_isTyping) return;
    _isTyping = false;
    _lastSentAt = null;
    unawaited(_sendTyping(false));
  }

  void dispose() {
    stop();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityTimeout, stop);
  }

  Future<void> _sendTyping(bool typing) async {
    try {
      await _rooms.setTyping(
        roomId,
        typing,
        timeoutMs: typing ? _inactivityTimeout.inMilliseconds : null,
      );
    } catch (e) {
      debugPrint('[Kohera] Failed to set typing: $e');
    }
  }
}
