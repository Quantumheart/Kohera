import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/services/state_event_resolver.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Event>(),
  MockSpec<User>(),
  MockSpec<Room>(),
])
import 'state_event_resolver_test.mocks.dart';

// ── Helpers ──────────────────────────────────────────────────

void _stubSender(MockEvent event, MockUser sender, String name) {
  when(sender.calcDisplayname()).thenReturn(name);
  when(event.senderFromMemoryOrFallback).thenReturn(sender);
  when(event.senderId).thenReturn('@sender:example.com');
  when(event.originServerTs).thenReturn(DateTime(2026, 1, 15, 14, 30));
}

void _stubTarget(MockEvent event, MockRoom room, MockUser target, String name) {
  when(target.calcDisplayname()).thenReturn(name);
  when(event.room).thenReturn(room);
  when(room.unsafeGetUserFromMemoryOrFallback(any)).thenReturn(target);
}

MockEvent _memberEvent({
  required MockUser sender,
  required MockRoom room,
  required MockUser target,
  required String senderName,
  required String targetName,
  required String targetId,
  required Map<String, Object?> content,
  Map<String, Object?>? prevContent,
}) {
  final event = MockEvent();
  _stubSender(event, sender, senderName);
  _stubTarget(event, room, target, targetName);
  when(event.type).thenReturn(EventTypes.RoomMember);
  when(event.stateKey).thenReturn(targetId);
  when(event.content).thenReturn(content);
  when(event.prevContent).thenReturn(prevContent);
  return event;
}

MockEvent _simpleEvent({
  required MockUser sender,
  required String senderName,
  required String type,
  required Map<String, Object?> content,
}) {
  final event = MockEvent();
  _stubSender(event, sender, senderName);
  when(event.type).thenReturn(type);
  when(event.content).thenReturn(content);
  return event;
}

// ── Tests ────────────────────────────────────────────────────

void main() {
  const resolver = StateEventResolver();
  late MockUser sender;
  late MockUser target;
  late MockRoom room;

  setUp(() {
    sender = MockUser();
    target = MockUser();
    room = MockRoom();
  });

  group('room name events', () {
    test('sets name', () {
      final event = _simpleEvent(
        sender: sender,
        senderName: 'Alice',
        type: EventTypes.RoomName,
        content: {'name': 'New Room'},
      );

      final result = resolver(event);

      expect(result.icon, Icons.edit_outlined);
      expect(result.text, "Alice changed the room name to 'New Room'");
      expect(result.replacementRoomId, isNull);
    });

    test('removes name', () {
      final event = _simpleEvent(
        sender: sender,
        senderName: 'Alice',
        type: EventTypes.RoomName,
        content: {'name': ''},
      );

      final result = resolver(event);

      expect(result.text, 'Alice removed the room name');
    });

    test('missing name field treated as empty', () {
      final event = _simpleEvent(
        sender: sender,
        senderName: 'Alice',
        type: EventTypes.RoomName,
        content: {},
      );

      final result = resolver(event);

      expect(result.text, 'Alice removed the room name');
    });
  });

  group('room topic events', () {
    test('sets topic', () {
      final event = _simpleEvent(
        sender: sender,
        senderName: 'Alice',
        type: EventTypes.RoomTopic,
        content: {'topic': 'New topic'},
      );

      final result = resolver(event);

      expect(result.icon, Icons.edit_outlined);
      expect(result.text, "Alice changed the topic to 'New topic'");
    });

    test('removes topic', () {
      final event = _simpleEvent(
        sender: sender,
        senderName: 'Alice',
        type: EventTypes.RoomTopic,
        content: {'topic': ''},
      );

      final result = resolver(event);

      expect(result.text, 'Alice removed the room topic');
    });
  });

  group('room avatar events', () {
    test('renders avatar change text', () {
      final event = _simpleEvent(
        sender: sender,
        senderName: 'Alice',
        type: EventTypes.RoomAvatar,
        content: {'url': 'mxc://example.com/avatar'},
      );

      final result = resolver(event);

      expect(result.icon, Icons.image_outlined);
      expect(result.text, 'Alice changed the room avatar');
    });
  });

  group('tombstone events', () {
    test('renders upgrade text with replacement room', () {
      final event = _simpleEvent(
        sender: sender,
        senderName: 'Alice',
        type: EventTypes.RoomTombstone,
        content: {
          'replacement_room': '!newroom:example.com',
          'body': 'We moved!',
        },
      );

      final result = resolver(event);

      expect(result.icon, Icons.upgrade_rounded);
      expect(
        result.text,
        'This room has been upgraded. We moved! Tap to open the new room.',
      );
      expect(result.replacementRoomId, '!newroom:example.com');
      expect(result.isTombstone, isTrue);
    });

    test('renders without body suffix when body is absent', () {
      final event = _simpleEvent(
        sender: sender,
        senderName: 'Alice',
        type: EventTypes.RoomTombstone,
        content: {'replacement_room': '!newroom:example.com'},
      );

      final result = resolver(event);

      expect(
        result.text,
        'This room has been upgraded. Tap to open the new room.',
      );
    });

    test('replacementRoomId is null when replacement_room is empty', () {
      final event = _simpleEvent(
        sender: sender,
        senderName: 'Alice',
        type: EventTypes.RoomTombstone,
        content: {'replacement_room': ''},
      );

      final result = resolver(event);

      expect(result.replacementRoomId, isNull);
      expect(result.isTombstone, isFalse);
    });
  });

  group('member events — join', () {
    test('join with no previous membership', () {
      final event = _memberEvent(
        sender: sender,
        room: room,
        target: target,
        senderName: 'Alice',
        targetName: 'Alice',
        targetId: '@alice:example.com',
        content: {'membership': 'join'},
      );

      final result = resolver(event);

      expect(result.icon, Icons.login_rounded);
      expect(result.text, 'Alice joined');
    });

    test('join with previous join and displayname change', () {
      final event = _memberEvent(
        sender: sender,
        room: room,
        target: target,
        senderName: 'Alice',
        targetName: 'Bob Ross',
        targetId: '@testuser2:example.com',
        content: {'membership': 'join', 'displayname': 'Bob Ross'},
        prevContent: {'membership': 'join', 'displayname': 'testuser2'},
      );

      final result = resolver(event);

      expect(result.icon, Icons.badge_outlined);
      expect(
        result.text,
        "testuser2 changed their display name to 'Bob Ross'",
      );
    });

    test('join with displayname change and empty prev displayname', () {
      final event = _memberEvent(
        sender: sender,
        room: room,
        target: target,
        senderName: 'Alice',
        targetName: 'Bob Ross',
        targetId: '@testuser2:example.com',
        content: {'membership': 'join', 'displayname': 'Bob Ross'},
        prevContent: {'membership': 'join'},
      );

      final result = resolver(event);

      expect(
        result.text,
        "testuser2 changed their display name to 'Bob Ross'",
      );
    });

    test('join with displayname removed', () {
      final event = _memberEvent(
        sender: sender,
        room: room,
        target: target,
        senderName: 'Alice',
        targetName: 'Old Name',
        targetId: '@user:example.com',
        content: {'membership': 'join'},
        prevContent: {'membership': 'join', 'displayname': 'Old Name'},
      );

      final result = resolver(event);

      expect(result.text, 'Old Name removed their display name');
    });

    test('join with avatar change', () {
      final event = _memberEvent(
        sender: sender,
        room: room,
        target: target,
        senderName: 'Alice',
        targetName: 'Bob',
        targetId: '@bob:example.com',
        content: {'membership': 'join', 'avatar_url': 'mxc://new'},
        prevContent: {'membership': 'join', 'avatar_url': 'mxc://old'},
      );

      final result = resolver(event);

      expect(result.icon, Icons.image_outlined);
      expect(result.text, 'Bob changed their avatar');
    });

    test('join with no visible changes', () {
      final event = _memberEvent(
        sender: sender,
        room: room,
        target: target,
        senderName: 'Alice',
        targetName: 'Bob',
        targetId: '@bob:example.com',
        content: {'membership': 'join', 'displayname': 'Bob'},
        prevContent: {'membership': 'join', 'displayname': 'Bob'},
      );

      final result = resolver(event);

      expect(result.icon, Icons.login_rounded);
      expect(result.text, 'Bob updated their profile');
    });
  });

  group('member events — invite', () {
    test('invite', () {
      final event = _memberEvent(
        sender: sender,
        room: room,
        target: target,
        senderName: 'Alice',
        targetName: 'Bob',
        targetId: '@bob:example.com',
        content: {'membership': 'invite'},
      );

      final result = resolver(event);

      expect(result.icon, Icons.person_add_alt_1_outlined);
      expect(result.text, 'Bob was invited by Alice');
    });
  });

  group('member events — leave', () {
    test('self-leave', () {
      final event = _memberEvent(
        sender: sender,
        room: room,
        target: target,
        senderName: 'Alice',
        targetName: 'Alice',
        targetId: '@sender:example.com',
        content: {'membership': 'leave'},
        prevContent: {'membership': 'join'},
      );

      final result = resolver(event);

      expect(result.icon, Icons.logout_rounded);
      expect(result.text, 'Alice left');
    });

    test('reject invite', () {
      final event = _memberEvent(
        sender: sender,
        room: room,
        target: target,
        senderName: 'Alice',
        targetName: 'Alice',
        targetId: '@sender:example.com',
        content: {'membership': 'leave'},
        prevContent: {'membership': 'invite'},
      );

      final result = resolver(event);

      expect(result.icon, Icons.cancel_outlined);
      expect(result.text, 'Alice rejected the invitation');
    });

    test('kicked by another user', () {
      final event = _memberEvent(
        sender: sender,
        room: room,
        target: target,
        senderName: 'Admin',
        targetName: 'Bob',
        targetId: '@bob:example.com',
        content: {'membership': 'leave', 'reason': 'spam'},
        prevContent: {'membership': 'join'},
      );

      final result = resolver(event);

      expect(result.icon, Icons.person_remove_outlined);
      expect(result.text, 'Bob was kicked by Admin (spam)');
    });

    test('kicked without reason', () {
      final event = _memberEvent(
        sender: sender,
        room: room,
        target: target,
        senderName: 'Admin',
        targetName: 'Bob',
        targetId: '@bob:example.com',
        content: {'membership': 'leave'},
        prevContent: {'membership': 'join'},
      );

      final result = resolver(event);

      expect(result.text, 'Bob was kicked by Admin');
    });
  });

  group('member events — ban', () {
    test('ban with reason', () {
      final event = _memberEvent(
        sender: sender,
        room: room,
        target: target,
        senderName: 'Admin',
        targetName: 'Bob',
        targetId: '@bob:example.com',
        content: {'membership': 'ban', 'reason': 'abuse'},
        prevContent: {'membership': 'join'},
      );

      final result = resolver(event);

      expect(result.icon, Icons.block_rounded);
      expect(result.text, 'Bob was banned by Admin (abuse)');
    });

    test('ban without reason', () {
      final event = _memberEvent(
        sender: sender,
        room: room,
        target: target,
        senderName: 'Admin',
        targetName: 'Bob',
        targetId: '@bob:example.com',
        content: {'membership': 'ban'},
        prevContent: {'membership': 'join'},
      );

      final result = resolver(event);

      expect(result.text, 'Bob was banned by Admin');
    });
  });

  group('member events — knock', () {
    test('knock', () {
      final event = _memberEvent(
        sender: sender,
        room: room,
        target: target,
        senderName: 'Alice',
        targetName: 'Bob',
        targetId: '@bob:example.com',
        content: {'membership': 'knock'},
      );

      final result = resolver(event);

      expect(result.icon, Icons.front_hand_outlined);
      expect(result.text, 'Bob requested to join');
    });
  });

  group('unknown event types', () {
    test('falls back to generic room updated', () {
      final event = _simpleEvent(
        sender: sender,
        senderName: 'Alice',
        type: 'm.room.history_visibility',
        content: {'history_visibility': 'shared'},
      );

      final result = resolver(event);

      expect(result.icon, Icons.info_outline);
      expect(result.text, 'Room updated');
    });

    test('unknown membership falls back to generic text', () {
      final event = _memberEvent(
        sender: sender,
        room: room,
        target: target,
        senderName: 'Alice',
        targetName: 'Bob',
        targetId: '@bob:example.com',
        content: {'membership': 'custom_state'},
      );

      final result = resolver(event);

      expect(result.icon, Icons.info_outline);
      expect(result.text, 'Membership changed');
    });
  });

  group('target name fallback', () {
    test('uses stateKey when target user lookup returns null name', () {
      final event = MockEvent();
      _stubSender(event, sender, 'Alice');
      when(event.type).thenReturn(EventTypes.RoomMember);
      when(event.stateKey).thenReturn('@unknown:example.com');
      when(event.content).thenReturn({'membership': 'invite'});
      when(event.room).thenReturn(room);
      when(room.unsafeGetUserFromMemoryOrFallback(any)).thenReturn(target);
      when(target.calcDisplayname()).thenReturn('@unknown:example.com');

      final result = resolver(event);

      expect(result.text, '@unknown:example.com was invited by Alice');
    });
  });
}
