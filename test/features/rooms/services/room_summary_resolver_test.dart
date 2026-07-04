import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/rooms/models/kohera_room_summary.dart';
import 'package:kohera/features/rooms/services/room_summary_resolver.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Room>(),
  MockSpec<Event>(),
  MockSpec<User>(),
])
import 'room_summary_resolver_test.mocks.dart';

void main() {
  late MockRoom room;
  late MockUser sender;

  setUp(() {
    room = MockRoom();
    sender = MockUser();

    when(room.id).thenReturn('!room:example.com');
    when(room.getLocalizedDisplayname()).thenReturn('My Room');
    when(room.avatar).thenReturn(null);
    when(room.topic).thenReturn('A topic');
    when(room.canonicalAlias).thenReturn('');
    when(room.isDirectChat).thenReturn(false);
    when(room.encrypted).thenReturn(false);
    when(room.notificationCount).thenReturn(0);
    when(room.highlightCount).thenReturn(0);
    when(room.typingUsers).thenReturn(<User>[]);
    when(room.pinnedEventIds).thenReturn(<String>[]);
    when(room.isSpace).thenReturn(false);
    when(room.isFavourite).thenReturn(false);
    when(room.lastEvent).thenReturn(null);
  });

  KoheraRoomSummary resolve() =>
      const RoomSummaryResolver()(room, myUserId: '@me:example.com');

  group('RoomSummaryResolver', () {
    test('maps core fields with no last event', () {
      final summary = resolve();

      expect(summary.roomId, '!room:example.com');
      expect(summary.displayname, 'My Room');
      expect(summary.topic, 'A topic');
      expect(summary.isDirectChat, isFalse);
      expect(summary.isEncrypted, isFalse);
      expect(summary.isSpace, isFalse);
      expect(summary.spaceChildCount, 0);
      expect(summary.lastEventPreview, 'No messages yet');
      expect(summary.lastEventTimestamp, isNull);
      expect(summary.typingDisplayNames, isEmpty);
    });

    test('lastEventPreview is the body for a text message', () {
      final event = MockEvent();
      when(event.type).thenReturn('m.room.message');
      when(event.messageType).thenReturn(MessageTypes.Text);
      when(event.body).thenReturn('hello world');
      when(event.redacted).thenReturn(false);
      when(event.content).thenReturn(<String, Object?>{'body': 'hello world'});
      when(event.senderFromMemoryOrFallback).thenReturn(sender);
      when(sender.calcDisplayname()).thenReturn('Alice');
      when(event.originServerTs).thenReturn(DateTime(2026, 1, 15, 10, 30));
      when(room.lastEvent).thenReturn(event);

      final summary = resolve();

      expect(summary.lastEventPreview, 'hello world');
      expect(summary.lastEventBody, 'hello world');
      expect(summary.lastEventSenderName, 'Alice');
      expect(summary.lastEventTimestamp, DateTime(2026, 1, 15, 10, 30));
    });

    test('lastEventPreview is "📷 Image" for an image message', () {
      final event = MockEvent();
      when(event.type).thenReturn('m.room.message');
      when(event.messageType).thenReturn(MessageTypes.Image);
      when(event.body).thenReturn('image.jpg');
      when(event.redacted).thenReturn(false);
      when(event.content).thenReturn(<String, Object?>{'body': 'image.jpg'});
      when(event.senderFromMemoryOrFallback).thenReturn(sender);
      when(sender.calcDisplayname()).thenReturn('Alice');
      when(room.lastEvent).thenReturn(event);

      expect(resolve().lastEventPreview, '📷 Image');
    });

    test('lastEventIsThreadReply is true when relationshipType is thread', () {
      final event = MockEvent();
      when(event.type).thenReturn('m.room.message');
      when(event.messageType).thenReturn(MessageTypes.Text);
      when(event.body).thenReturn('reply');
      when(event.redacted).thenReturn(false);
      when(event.content).thenReturn(<String, Object?>{'body': 'reply'});
      when(event.relationshipType).thenReturn(RelationshipTypes.thread);
      when(event.senderFromMemoryOrFallback).thenReturn(sender);
      when(sender.calcDisplayname()).thenReturn('Alice');
      when(room.lastEvent).thenReturn(event);

      expect(resolve().lastEventIsThreadReply, isTrue);
    });

    test('spaceChildCount is the child count for a space', () {
      when(room.isSpace).thenReturn(true);
      when(room.spaceChildren).thenReturn(List.empty());

      final summary = resolve();
      expect(summary.isSpace, isTrue);
      expect(summary.spaceChildCount, 0);
    });

    test('typingDisplayNames excludes the current user', () {
      final alice = MockUser();
      final bob = MockUser();
      when(alice.id).thenReturn('@alice:example.com');
      when(alice.displayName).thenReturn('Alice');
      when(bob.id).thenReturn('@me:example.com');
      when(bob.displayName).thenReturn('Me');
      when(room.typingUsers).thenReturn([alice, bob]);

      expect(resolve().typingDisplayNames, ['Alice']);
    });
  });
}
