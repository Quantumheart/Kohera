import 'package:flutter/foundation.dart';
import 'package:kohera/data/models/kohera_media_content.dart';
import 'package:kohera/data/models/kohera_message_display.dart';
import 'package:kohera/data/models/kohera_poll.dart';
import 'package:kohera/data/models/kohera_reaction.dart';
import 'package:kohera/data/models/kohera_state_event_text.dart';

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
    this.display,
    this.reactions,
    this.poll,
    this.stateEventText,
    this.media,
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

  /// The pre-resolved display model (body, sender, status, edit/thread
  /// state). Null for events converted without display resolution.
  final KoheraMessageDisplay? display;

  /// The pre-resolved reaction list, non-null when reaction aggregation
  /// existed at conversion time.
  final KoheraReactionList? reactions;

  /// The pre-resolved poll state (only for poll-start events).
  final KoheraPoll? poll;

  /// The pre-resolved state event text (only for renderable state events).
  final KoheraStateEventText? stateEventText;

  /// The pre-resolved media content (only for sticker and message events).
  final KoheraMediaContent? media;

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
