import 'package:kohera/data/models/kohera_timeline_event.dart';
import 'package:matrix/matrix.dart';

/// Converts Matrix SDK [Event]s into [KoheraTimelineEvent] domain models.
///
/// This is the conversion boundary for `Event` → `KoheraTimelineEvent`.
/// Aggregation state is flattened with the [Timeline] the event belongs
/// to, so feature code can query reaction / thread / edit counts without
/// holding SDK objects.
class TimelineResolver {
  const TimelineResolver();

  /// The relationship types flattened into
  /// [KoheraTimelineEvent.aggregatedEventIds].
  static const List<String> aggregationTypes = [
    RelationshipTypes.reaction,
    RelationshipTypes.thread,
    RelationshipTypes.edit,
    RelationshipTypes.reference,
  ];

  /// Converts [event], resolving aggregation state against [timeline].
  KoheraTimelineEvent convert(Event event, {Timeline? timeline}) {
    final aggregated = <String, List<String>>{};
    if (timeline != null) {
      for (final type in aggregationTypes) {
        if (!event.hasAggregatedEvents(timeline, type)) continue;
        aggregated[type] = event
            .aggregatedEvents(timeline, type)
            .map((e) => e.eventId)
            .toList(growable: false);
      }
    }
    return KoheraTimelineEvent(
      eventId: event.eventId,
      senderId: event.senderId,
      type: event.type,
      messageType: event.messageType,
      body: event.body,
      originServerTs: event.originServerTs,
      redacted: event.redacted,
      canRedact: event.canRedact,
      content: Map<String, Object?>.from(event.content),
      relationshipType: event.relationshipType,
      relationshipEventId: event.relationshipEventId,
      prevContent: event.prevContent == null
          ? null
          : Map<String, Object?>.from(event.prevContent!),
      aggregatedEventIds: aggregated,
    );
  }

  /// Converts the current [timeline] event list.
  List<KoheraTimelineEvent> convertTimeline(Timeline timeline) {
    return timeline.events
        .map((e) => convert(e, timeline: timeline))
        .toList(growable: false);
  }
}
