import 'package:flutter/foundation.dart';

/// SDK-free view of a single sync or notification event.
///
/// Carries the raw content map plus the envelope fields the notifications
/// feature needs. Conversion from SDK types happens in `lib/data/resolvers/`.
@immutable
class KoheraSyncEvent {
  const KoheraSyncEvent({
    required this.type,
    required this.senderId,
    required this.content,
    this.stateKey,
    this.eventId,
    this.originServerTs,
  });

  /// The wire event type (see `KoheraEventTypes`).
  final String type;

  /// The sender's Matrix ID.
  final String senderId;

  /// The raw event content.
  final Map<String, Object?> content;

  /// The state key for state events (invite state), else null.
  final String? stateKey;

  /// The event ID, or null for stripped state events.
  final String? eventId;

  /// The server timestamp, or null for stripped state events.
  final DateTime? originServerTs;

  /// The `body` content field, or an empty string.
  String get body => content['body'] as String? ?? '';
}
