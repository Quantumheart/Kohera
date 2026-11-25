import 'package:kohera/data/models/kohera_push_notification.dart';
import 'package:kohera/data/resolvers/sync_update_resolver.dart';
import 'package:matrix/matrix.dart' as matrix_sdk;

/// Conversion boundary: SDK [matrix_sdk.Notification] to
/// [KoheraPushNotification].
class PushNotificationResolver {
  const PushNotificationResolver();

  KoheraPushNotification convert(matrix_sdk.Notification notification) =>
      KoheraPushNotification(
        event: SyncUpdateResolver.convertEvent(notification.event),
        roomId: notification.roomId,
        timestampMs: notification.ts,
        isRead: notification.read,
        hasHighlight: _hasHighlightAction(notification.actions),
      );

  static bool _hasHighlightAction(List<Object?> actions) {
    for (final action in actions) {
      if (action is Map && action['set_tweak'] == 'highlight') {
        final value = action['value'];
        if (value == null || value == true) return true;
      }
    }
    return false;
  }
}
