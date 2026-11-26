import 'package:flutter/foundation.dart';

/// SDK-free view of a single timeline event.
///
/// Carries the envelope fields plus the raw content maps the chat feature
/// needs to classify, filter, and render messages. Aggregation state
/// (reactions, thread replies, edits, references) is flattened to event-ID
/// lists keyed by relationship type. Conversion from SDK types happens in
/// `TimelineResolver` (`lib/data/resolvers/`).
@immutable
class KoheraTimelineEvent {
  const KoheraTimelineEvent({
    required this.eventId,
    required this.senderId,
    required this.type,
    required this.body,
    required this.originServerTs,
    required this.redacted,
    required this.canRedact,
    required this.content,
    this.messageType,
    this.relationshipType,
    this.relationshipEventId,
    this.prevContent,
    this.aggregatedEventIds = const {},
  });

  /// The Matrix event ID.
  final String eventId;

  /// The sender's Matrix ID.
  final String senderId;

  /// The wire event type (see `KoheraEventTypes`).
  final String type;

  /// The `msgtype` for `m.room.message` events, else null.
  final String? messageType;

  /// The display body (decrypted when applicable).
  final String body;

  /// The server timestamp.
  final DateTime originServerTs;

  /// Whether the event has been redacted.
  final bool redacted;

  /// Whether the local user may redact this event.
  final bool canRedact;

  /// The raw event content.
  final Map<String, Object?> content;

  /// The `m.relates_to` relationship type (e.g. `m.thread`), else null.
  final String? relationshipType;

  /// The `m.relates_to` target event ID, else null.
  final String? relationshipEventId;

  /// The previous content for state events (`prev_content`), else null.
  final Map<String, Object?>? prevContent;

  /// Aggregated event IDs keyed by relationship type (`m.annotation`,
  /// `m.thread`, `m.replace`, `m.reference`).
  final Map<String, List<String>> aggregatedEventIds;

  /// The [content] value at [key] when it is a [String], else null.
  String? contentString(String key) {
    final value = content[key];
    return value is String ? value : null;
  }

  /// Whether any events aggregate this event with [relationshipType].
  bool hasAggregation(String relationshipType) =>
      (aggregatedEventIds[relationshipType] ?? const []).isNotEmpty;

  /// The number of events aggregating this event with [relationshipType].
  int aggregationCount(String relationshipType) =>
      aggregatedEventIds[relationshipType]?.length ?? 0;
}
