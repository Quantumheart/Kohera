import 'package:kohera/data/models/kohera_media_content.dart';
import 'package:kohera/data/models/kohera_poll.dart';
import 'package:kohera/data/models/kohera_reaction.dart';
import 'package:kohera/data/models/kohera_state_event_text.dart';
import 'package:kohera/data/models/kohera_timeline_event.dart';
import 'package:kohera/data/resolvers/media_content_resolver.dart';
import 'package:kohera/data/resolvers/message_display_resolver.dart';
import 'package:kohera/data/resolvers/poll_resolver.dart';
import 'package:kohera/data/resolvers/reaction_resolver.dart';
import 'package:kohera/data/resolvers/state_event_resolver.dart';
import 'package:matrix/matrix.dart';

/// Converts Matrix SDK [Event]s into [KoheraTimelineEvent] domain models.
///
/// This is the conversion boundary for `Event` → `KoheraTimelineEvent`.
/// Aggregation state is flattened with the [Timeline] the event belongs
/// to, so feature code can query reaction / thread / edit counts without
/// holding SDK objects. Display, reaction, poll, state-event, and media
/// models are pre-resolved here while SDK access is available.
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

  /// Event types rendered as state events in the timeline.
  static const Set<String> stateEventTypes = {
    EventTypes.RoomName,
    EventTypes.RoomTopic,
    EventTypes.RoomAvatar,
    EventTypes.RoomTombstone,
    EventTypes.RoomMember,
  };

  /// Converts [event], resolving aggregation state against [timeline].
  ///
  /// [myUserId] feeds reaction `reactedByMe` and poll selection state.
  KoheraTimelineEvent convert(
    Event event, {
    Timeline? timeline,
    String? myUserId,
  }) {
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

    final display = MessageDisplayResolver.resolve(event, timeline: timeline);

    KoheraReactionList? reactions;
    if (timeline != null &&
        event.hasAggregatedEvents(timeline, RelationshipTypes.reaction)) {
      reactions = ReactionResolver.resolve(
        event,
        timeline,
        myUserId: myUserId ?? '',
      );
    }

    KoheraPoll? poll;
    if (timeline != null && event.type == PollEventContent.startType) {
      poll = PollResolver.resolve(
        event,
        timeline,
        myUserId: myUserId ?? '',
        canRedact: event.canRedact,
      );
    }

    KoheraStateEventText? stateEventText;
    if (stateEventTypes.contains(event.type)) {
      stateEventText = StateEventResolver.resolve(event);
    }

    KoheraMediaContent? media;
    if (event.type == EventTypes.Sticker ||
        event.type == EventTypes.Message) {
      media = MediaContentResolver.resolve(event);
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
      display: display,
      reactions: reactions,
      poll: poll,
      stateEventText: stateEventText,
      media: media,
    );
  }

  /// Converts the current [timeline] event list.
  List<KoheraTimelineEvent> convertTimeline(
    Timeline timeline, {
    String? myUserId,
  }) {
    return timeline.events
        .map((e) => convert(e, timeline: timeline, myUserId: myUserId))
        .toList(growable: false);
  }
}
