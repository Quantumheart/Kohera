import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

class PresenceService extends ChangeNotifier {
  PresenceService({required Client client}) : _client = client {
    _sub = _client.onPresenceChanged.stream.listen(_onPresenceChanged);
  }

  final Client _client;
  StreamSubscription<CachedPresence>? _sub;

  final Map<String, CachedPresence> _presences = {};

  bool _publishingEnabled = true;
  PresenceType? _desired;

  // ── Consuming ───────────────────────────────────────────────────

  CachedPresence? presenceFor(String userId) => _presences[userId];

  void _onPresenceChanged(CachedPresence presence) {
    _presences[presence.userid] = presence;
    notifyListeners();
  }

  // ── Publishing ──────────────────────────────────────────────────

  bool get publishingEnabled => _publishingEnabled;

  void setPublishingEnabled(bool enabled) {
    if (_publishingEnabled == enabled) return;
    _publishingEnabled = enabled;
    if (!enabled) {
      _apply(PresenceType.offline);
    } else if (_desired != null) {
      _apply(_desired!);
    }
    notifyListeners();
  }

  void setOnline() => _publish(PresenceType.online);

  void setAway() => _publish(PresenceType.unavailable);

  void setOffline() => _publish(PresenceType.offline);

  void _publish(PresenceType type) {
    _desired = type;
    if (!_publishingEnabled) return;
    _apply(type);
  }

  void _apply(PresenceType type) {
    if (_client.syncPresence == type) return;
    _client.syncPresence = type;
    debugPrint('[Kohera] Presence → ${type.name}');
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }
}
