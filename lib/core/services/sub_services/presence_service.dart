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

  /// Human-readable presence line for a user, or null when unknown.
  String? presenceLabel(String userId) {
    final p = _presences[userId];
    if (p == null) return null;
    final lastSeen = p.lastActiveTimestamp;
    switch (p.presence) {
      case PresenceType.online:
        return 'Online';
      case PresenceType.unavailable:
        return lastSeen != null ? 'Away · last seen ${_ago(lastSeen)}' : 'Away';
      case PresenceType.offline:
        return lastSeen != null
            ? 'Offline · last seen ${_ago(lastSeen)}'
            : 'Offline';
    }
  }

  static String _ago(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }

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
