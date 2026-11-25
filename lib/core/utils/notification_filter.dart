import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/utils/word_boundary.dart';

// ── Notification-level-aware unread count ───────────────────

/// Effective unread count filtered by the global notification level.
/// Shared between the room list UI and the OS notification service.
///
/// [notificationCount] and [highlightCount] come from the room summary;
/// [lastEventBody] is the lowercase-scanned body of the room's last event.
int effectiveUnreadCount({
  required int notificationCount,
  required int highlightCount,
  required String? lastEventBody,
  required PreferencesService prefs,
}) {
  switch (prefs.notificationLevel) {
    case NotificationLevel.all:
      return notificationCount;
    case NotificationLevel.off:
      return 0;
    case NotificationLevel.mentionsOnly:
      if (highlightCount > 0) return highlightCount;
      final body = lastEventBody?.toLowerCase();
      if (body == null) return 0;
      for (final kw in prefs.notificationKeywords) {
        if (kw.isNotEmpty && body.contains(kw)) return 1;
      }
      return 0;
  }
}

/// Whether a specific message event should trigger an OS notification
/// under the current notification level and custom keywords.
///
/// For mention detection this checks whether the event body contains the
/// user's Matrix ID or display name ([ownLowerDisplayName], lowercased),
/// rather than relying on the room-level highlight count which is stale
/// across multiple events.
bool shouldNotifyForEvent({
  required String eventBody,
  required String? senderId,
  required String? ownUserId,
  required String? ownLowerDisplayName,
  required PreferencesService prefs,
}) {
  if (senderId == ownUserId) return false;

  switch (prefs.notificationLevel) {
    case NotificationLevel.off:
      return false;
    case NotificationLevel.all:
      return true;
    case NotificationLevel.mentionsOnly:
      final lower = eventBody.toLowerCase();
      final lowerUserId = ownUserId?.toLowerCase();
      if (lowerUserId != null && lower.contains(lowerUserId)) {
        return true;
      }
      if (ownLowerDisplayName != null &&
          ownLowerDisplayName.length >= 2 &&
          containsWord(lower, ownLowerDisplayName)) {
        return true;
      }
      for (final kw in prefs.notificationKeywords) {
        if (kw.isNotEmpty && lower.contains(kw)) return true;
      }
      return false;
  }
}
