import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/rooms/models/kohera_room_member.dart';

void main() {
  group('KoheraRoomMember', () {
    test('constructs with all fields', () {
      const member = KoheraRoomMember(
        userId: '@alice:example.com',
        displayname: 'Alice',
        avatarUrl: 'mxc://example.com/avatar',
        membership: 'join',
        powerLevel: 100,
      );

      expect(member.userId, '@alice:example.com');
      expect(member.displayname, 'Alice');
      expect(member.avatarUrl, 'mxc://example.com/avatar');
      expect(member.membership, 'join');
      expect(member.powerLevel, 100);
    });

    test('isBanned is true when membership is ban', () {
      const member = KoheraRoomMember(
        userId: '@bob:example.com',
        displayname: 'Bob',
        membership: 'ban',
        powerLevel: 0,
      );
      expect(member.isBanned, isTrue);
    });

    test('isBanned is false when membership is join', () {
      const member = KoheraRoomMember(
        userId: '@bob:example.com',
        displayname: 'Bob',
        membership: 'join',
        powerLevel: 0,
      );
      expect(member.isBanned, isFalse);
    });

    test('equality is based on userId', () {
      const a = KoheraRoomMember(
        userId: '@alice:example.com',
        displayname: 'Alice',
        membership: 'join',
        powerLevel: 100,
      );
      const b = KoheraRoomMember(
        userId: '@alice:example.com',
        displayname: 'Alice 2',
        membership: 'ban',
        powerLevel: 0,
      );
      const c = KoheraRoomMember(
        userId: '@bob:example.com',
        displayname: 'Bob',
        membership: 'join',
        powerLevel: 0,
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('copyWith preserves un-overridden fields', () {
      const member = KoheraRoomMember(
        userId: '@alice:example.com',
        displayname: 'Alice',
        avatarUrl: 'mxc://example.com/avatar',
        membership: 'join',
        powerLevel: 50,
      );

      final copy = member.copyWith(powerLevel: 100);
      expect(copy.userId, '@alice:example.com');
      expect(copy.displayname, 'Alice');
      expect(copy.avatarUrl, 'mxc://example.com/avatar');
      expect(copy.membership, 'join');
      expect(copy.powerLevel, 100);
    });

    test('toString includes userId and powerLevel', () {
      const member = KoheraRoomMember(
        userId: '@alice:example.com',
        displayname: 'Alice',
        membership: 'join',
        powerLevel: 50,
      );
      final str = member.toString();
      expect(str, contains('@alice:example.com'));
      expect(str, contains('50'));
    });
  });

  group('KoheraRoomMemberList', () {
    test('isEmpty is true for empty list', () {
      const list = KoheraRoomMemberList(
        members: [],
        participantListComplete: false,
        memberCount: 0,
      );
      expect(list.isEmpty, isTrue);
      expect(list.isNotEmpty, isFalse);
    });

    test('isNotEmpty is true for non-empty list', () {
      const list = KoheraRoomMemberList(
        members: [
          KoheraRoomMember(
            userId: '@a:example.com',
            displayname: 'A',
            membership: 'join',
            powerLevel: 0,
          ),
        ],
        participantListComplete: true,
        memberCount: 1,
      );
      expect(list.isEmpty, isFalse);
      expect(list.isNotEmpty, isTrue);
    });

    test('toString includes member count', () {
      const list = KoheraRoomMemberList(
        members: [
          KoheraRoomMember(
            userId: '@a:example.com',
            displayname: 'A',
            membership: 'join',
            powerLevel: 0,
          ),
          KoheraRoomMember(
            userId: '@b:example.com',
            displayname: 'B',
            membership: 'join',
            powerLevel: 50,
          ),
        ],
        participantListComplete: true,
        memberCount: 2,
      );
      expect(list.toString(), contains('2 members'));
    });
  });
}
