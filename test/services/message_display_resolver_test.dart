import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/models/kohera_message_status.dart';
import 'package:kohera/features/chat/services/message_display_resolver.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Event>(),
  MockSpec<User>(),
  MockSpec<Room>(),
  MockSpec<Timeline>(),
])
import 'message_display_resolver_test.mocks.dart';

void main() {
  late MockEvent event;
  late MockUser sender;
  late MockRoom room;

  setUp(() {
    event = MockEvent();
    sender = MockUser();
    room = MockRoom();

    when(event.eventId).thenReturn(r'$123:server');
    when(event.senderId).thenReturn('@alice:server');
    when(event.type).thenReturn('m.room.message');
    when(event.originServerTs).thenReturn(DateTime(2026, 1, 15, 10, 30));
    when(event.senderFromMemoryOrFallback).thenReturn(sender);
    when(event.room).thenReturn(room);
    when(sender.calcDisplayname()).thenReturn('Alice');
    when(sender.avatarUrl).thenReturn(null);
    when(event.content).thenReturn(<String, Object?>{
      'body': 'hello',
      'msgtype': 'm.text',
    });
    when(event.body).thenReturn('hello');
    when(event.messageType).thenReturn('m.text');
    when(event.redacted).thenReturn(false);
    when(event.redactedBecause).thenReturn(null);
    when(event.transactionId).thenReturn(null);
    when(event.status).thenReturn(EventStatus.synced);
    when(event.formattedText).thenReturn('');
  });

  group('MessageDisplayResolver', () {
    test('converts basic text message', () {
      final message = const MessageDisplayResolver()(event);

      expect(message.eventId, r'$123:server');
      expect(message.senderId, '@alice:server');
      expect(message.senderName, 'Alice');
      expect(message.body, 'hello');
      expect(message.messageType, 'm.text');
      expect(message.eventType, 'm.room.message');
      expect(message.isRedacted, false);
      expect(message.status, KoheraMessageStatus.sent);
      expect(message.isEdited, false);
      expect(message.formattedHtml, isNull);
    });

    test('converts HTML message', () {
      when(event.content).thenReturn(<String, Object?>{
        'body': 'hello',
        'msgtype': 'm.text',
        'format': 'org.matrix.custom.html',
        'formatted_body': '<b>hello</b>',
      });
      when(event.formattedText).thenReturn('<b>hello</b>');

      final message = const MessageDisplayResolver()(event);

      expect(message.formattedHtml, '<b>hello</b>');
    });

    test('non-HTML formatted text is ignored', () {
      when(event.formattedText).thenReturn('some text');
      when(event.content).thenReturn(<String, Object?>{
        'body': 'hello',
        'msgtype': 'm.text',
      });

      final message = const MessageDisplayResolver()(event);

      expect(message.formattedHtml, isNull);
    });

    test('converts redacted message with redactor', () {
      final redactedBecause = MockEvent();
      final redactorUser = MockUser();

      when(event.redacted).thenReturn(true);
      when(event.redactedBecause).thenReturn(redactedBecause);
      when(redactedBecause.senderId).thenReturn('@bob:server');
      when(redactedBecause.content).thenReturn(<String, Object?>{
        'reason': 'spam',
      });
      when(room.unsafeGetUserFromMemoryOrFallback('@bob:server'))
          .thenReturn(redactorUser);
      when(redactorUser.displayName).thenReturn('Bob');

      final message = const MessageDisplayResolver()(event);

      expect(message.isRedacted, true);
      expect(message.redactorId, '@bob:server');
      expect(message.redactorName, 'Bob');
      expect(message.redactionReason, 'spam');
    });

    test('self-redact has no redactorName', () {
      final redactedBecause = MockEvent();
      when(event.redacted).thenReturn(true);
      when(event.redactedBecause).thenReturn(redactedBecause);
      when(redactedBecause.senderId).thenReturn('@alice:server');
      when(redactedBecause.content).thenReturn(<String, Object?>{});

      final message = const MessageDisplayResolver()(event);

      expect(message.isRedacted, true);
      expect(message.redactorId, '@alice:server');
      expect(message.redactorName, isNull);
    });

    test('converts sending status', () {
      when(event.status).thenReturn(EventStatus.sending);

      final message = const MessageDisplayResolver()(event);

      expect(message.status, KoheraMessageStatus.sending);
    });

    test('converts error status', () {
      when(event.status).thenReturn(EventStatus.error);

      final message = const MessageDisplayResolver()(event);

      expect(message.status, KoheraMessageStatus.error);
    });

    test('strips reply fallback from body when replyEventId present', () {
      when(event.content).thenReturn(<String, Object?>{
        'body': '> <@bob:server> original\n\nreply text',
        'msgtype': 'm.text',
        'm.relates_to': {
          'm.in_reply_to': {'event_id': r'$orig:server'},
        },
      });
      when(event.body).thenReturn('> <@bob:server> original\n\nreply text');

      final message = const MessageDisplayResolver()(event);

      expect(message.replyEventId, r'$orig:server');
      expect(message.body, 'reply text');
    });

    test('detects thread root via aggregated events', () {
      final timeline = MockTimeline();
      when(event.hasAggregatedEvents(timeline, RelationshipTypes.thread))
          .thenReturn(true);
      when(event.hasAggregatedEvents(timeline, RelationshipTypes.edit))
          .thenReturn(false);
      when(event.getDisplayEvent(timeline)).thenReturn(event);

      final message = const MessageDisplayResolver()(
        event,
        timeline: timeline,
      );

      expect(message.threadRootId, r'$123:server');
      expect(message.isEdited, false);
    });

    test('detects edit via aggregated events', () {
      final timeline = MockTimeline();
      when(event.hasAggregatedEvents(timeline, RelationshipTypes.thread))
          .thenReturn(false);
      when(event.hasAggregatedEvents(timeline, RelationshipTypes.edit))
          .thenReturn(true);
      when(event.getDisplayEvent(timeline)).thenReturn(event);

      final message = const MessageDisplayResolver()(
        event,
        timeline: timeline,
      );

      expect(message.isEdited, true);
    });
  });
}
