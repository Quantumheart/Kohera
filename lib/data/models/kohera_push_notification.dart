import 'package:flutter/foundation.dart';
import 'package:kohera/data/models/kohera_sync_event.dart';

/// SDK-free view of one entry from the `/notifications` endpoint.
@immutable
class KoheraPushNotification {
  const KoheraPushNotification({
    required this.event,
    required this.roomId,
    required this.timestampMs,
    required this.isRead,
    required this.hasHighlight,
  });

  /// The notifying event. [KoheraSyncEvent.eventId] and
  /// [KoheraSyncEvent.originServerTs] are always set.
  final KoheraSyncEvent event;

  /// The room the event belongs to.
  final String roomId;

  /// The notification timestamp in milliseconds since epoch.
  final int timestampMs;

  /// Whether the notification has been read.
  final bool isRead;

  /// Whether the notification's actions include a highlight tweak.
  final bool hasHighlight;
}
