import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/resolvers/timeline_resolver.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'timeline_resolver_test.mocks.dart';

@GenerateNiceMocks([MockSpec<Event>(), MockSpec<Timeline>(), MockSpec<User>()])
void main() {
  late MockEvent event;
  late MockTimeline timeline;

  setUp(() {
    event = MockEvent();
    timeline = MockTimeline();

    final sender = MockUser();
    when(sender.calcDisplayname()).thenReturn('Alice');
    when(sender.displayName).thenReturn('Alice');
    when(sender.avatarUrl).thenReturn(null);

    when(event.eventId).thenReturn(r'$evt1:server');
    when(event.senderId).thenReturn('@alice:server');
    when(event.type).thenReturn(EventTypes.Message);
    when(event.messageType).thenReturn(MessageTypes.Text);
    when(event.body).thenReturn('hello');
    when(event.originServerTs).thenReturn(DateTime(2026, 2, 1, 12));
    when(event.redacted).thenReturn(false);
    when(event.canRedact).thenReturn(true);
    when(event.content).thenReturn(<String, Object?>{
      'msgtype': MessageTypes.Text,
      'body': 'hello',
    });
    when(event.relationshipType).thenReturn(null);
    when(event.relationshipEventId).thenReturn(null);
    when(event.prevContent).thenReturn(null);
    when(event.hasAggregatedEvents(timeline, any)).thenReturn(false);
    when(event.getDisplayEvent(any)).thenReturn(event);
    when(event.senderFromMemoryOrFallback).thenReturn(sender);
    when(event.status).thenReturn(EventStatus.synced);
    when(event.transactionId).thenReturn(null);
    when(event.formattedText).thenReturn('');
    when(event.attachmentMxcUrl).thenReturn(null);
  });

  group('TimelineResolver.convert', () {
    test('maps envelope fields', () {
      final result = const TimelineResolver().convert(event);

      expect(result.eventId, r'$evt1:server');
      expect(result.senderId, '@alice:server');
      expect(result.type, EventTypes.Message);
      expect(result.messageType, MessageTypes.Text);
      expect(result.body, 'hello');
      expect(result.originServerTs, DateTime(2026, 2, 1, 12));
      expect(result.redacted, isFalse);
      expect(result.canRedact, isTrue);
      expect(result.content['body'], 'hello');
      expect(result.relationshipType, isNull);
      expect(result.relationshipEventId, isNull);
      expect(result.prevContent, isNull);
      expect(result.aggregatedEventIds, isEmpty);
      expect(result.display, isNotNull);
      expect(result.display!.senderName, 'Alice');
      expect(result.media, isNotNull);
      expect(result.reactions, isNull);
      expect(result.poll, isNull);
      expect(result.stateEventText, isNull);
    });

    test('resolves state event text for member events', () {
      when(event.type).thenReturn(EventTypes.RoomMember);
      when(event.content).thenReturn(<String, Object?>{
        'membership': 'join',
        'displayname': 'Alice',
      });

      final result = const TimelineResolver().convert(event);

      expect(result.stateEventText, isNotNull);
      expect(result.media, isNull);
    });

    test('maps relationship fields for thread replies', () {
      when(event.relationshipType).thenReturn(RelationshipTypes.thread);
      when(event.relationshipEventId).thenReturn(r'$root:server');

      final result = const TimelineResolver().convert(event);

      expect(result.relationshipType, RelationshipTypes.thread);
      expect(result.relationshipEventId, r'$root:server');
    });

    test('copies prevContent when present', () {
      when(event.prevContent).thenReturn(<String, Object?>{
        'membership': 'join',
        'displayname': 'Alice',
      });

      final result = const TimelineResolver().convert(event);

      expect(result.prevContent, isNotNull);
      expect(result.prevContent!['membership'], 'join');
    });

    test('contentString returns string values only', () {
      when(event.content).thenReturn(<String, Object?>{
        'body': 'hello',
        'm.relates_to': <String, Object?>{'rel_type': 'm.thread'},
      });

      final result = const TimelineResolver().convert(event);

      expect(result.contentString('body'), 'hello');
      expect(result.contentString('m.relates_to'), isNull);
      expect(result.contentString('missing'), isNull);
    });

    test('flattens aggregated events per relationship type', () {
      final reaction1 = MockEvent();
      final reaction2 = MockEvent();
      final reply = MockEvent();
      when(reaction1.eventId).thenReturn(r'$r1:server');
      when(reaction2.eventId).thenReturn(r'$r2:server');
      when(reply.eventId).thenReturn(r'$t1:server');

      when(event.hasAggregatedEvents(timeline, RelationshipTypes.reaction))
          .thenReturn(true);
      when(event.aggregatedEvents(timeline, RelationshipTypes.reaction))
          .thenReturn({reaction1, reaction2});
      when(event.hasAggregatedEvents(timeline, RelationshipTypes.thread))
          .thenReturn(true);
      when(event.aggregatedEvents(timeline, RelationshipTypes.thread))
          .thenReturn({reply});

      final result =
          const TimelineResolver().convert(event, timeline: timeline);

      expect(result.hasAggregation(RelationshipTypes.reaction), isTrue);
      expect(result.aggregationCount(RelationshipTypes.reaction), 2);
      expect(
        result.aggregatedEventIds[RelationshipTypes.reaction],
        containsAll([r'$r1:server', r'$r2:server']),
      );
      expect(result.aggregationCount(RelationshipTypes.thread), 1);
      expect(result.hasAggregation(RelationshipTypes.edit), isFalse);
      expect(result.aggregationCount(RelationshipTypes.reference), 0);
    });

    test('skips aggregation when timeline is null', () {
      final result = const TimelineResolver().convert(event);

      expect(result.aggregatedEventIds, isEmpty);
    });
  });

  group('TimelineResolver.convertTimeline', () {
    test('converts every event in the timeline', () {
      final other = MockEvent();
      final otherSender = MockUser();
      when(otherSender.calcDisplayname()).thenReturn('Bob');
      when(other.eventId).thenReturn(r'$evt2:server');
      when(other.senderId).thenReturn('@bob:server');
      when(other.type).thenReturn(EventTypes.RoomMember);
      when(other.body).thenReturn('');
      when(other.originServerTs).thenReturn(DateTime(2026, 2, 1, 11));
      when(other.redacted).thenReturn(false);
      when(other.canRedact).thenReturn(false);
      when(other.content).thenReturn(<String, Object?>{'membership': 'join'});
      when(other.relationshipType).thenReturn(null);
      when(other.relationshipEventId).thenReturn(null);
      when(other.prevContent).thenReturn(null);
      when(other.hasAggregatedEvents(timeline, any)).thenReturn(false);
      when(other.getDisplayEvent(any)).thenReturn(other);
      when(other.senderFromMemoryOrFallback).thenReturn(otherSender);
      when(other.status).thenReturn(EventStatus.synced);
      when(other.transactionId).thenReturn(null);
      when(other.formattedText).thenReturn('');

      when(timeline.events).thenReturn([event, other]);

      final result = const TimelineResolver().convertTimeline(timeline);

      expect(result, hasLength(2));
      expect(result[0].eventId, r'$evt1:server');
      expect(result[1].eventId, r'$evt2:server');
      expect(result[1].type, EventTypes.RoomMember);
    });
  });
}
