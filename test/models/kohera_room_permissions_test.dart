import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/rooms/models/kohera_room_member.dart';
import 'package:kohera/features/rooms/models/kohera_room_permissions.dart';

void main() {
  group('KoheraJoinRule', () {
    test('label returns correct display text', () {
      expect(KoheraJoinRule.public.label, 'Public');
      expect(KoheraJoinRule.invite.label, 'Invite-only');
      expect(KoheraJoinRule.knock.label, 'Knock');
      expect(KoheraJoinRule.restricted.label, 'Restricted');
    });

    test('description returns non-empty text', () {
      for (final rule in KoheraJoinRule.values) {
        expect(rule.description, isNotEmpty);
      }
    });

    test('wire returns correct string', () {
      expect(KoheraJoinRule.public.wire, 'public');
      expect(KoheraJoinRule.invite.wire, 'invite');
      expect(KoheraJoinRule.knock.wire, 'knock');
      expect(KoheraJoinRule.restricted.wire, 'restricted');
    });
  });

  group('KoheraRoomMember', () {
    test('equality is based on userId', () {
      const a = KoheraRoomMember(
        userId: '@alice:e.com',
        displayname: 'Alice',
        membership: 'join',
        powerLevel: 100,
      );
      const b = KoheraRoomMember(
        userId: '@alice:e.com',
        displayname: 'Alice 2',
        membership: 'join',
        powerLevel: 50,
      );
      const c = KoheraRoomMember(
        userId: '@bob:e.com',
        displayname: 'Bob',
        membership: 'join',
        powerLevel: 0,
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toString includes userId', () {
      const m = KoheraRoomMember(
        userId: '@alice:e.com',
        displayname: 'Alice',
        membership: 'join',
        powerLevel: 50,
      );
      expect(m.toString(), contains('@alice:e.com'));
    });
  });

  group('KoheraRoomPermissions', () {
    test('constructs with all fields', () {
      const perms = KoheraRoomPermissions(
        roomId: '!r:e.com',
        displayName: 'Test Room',
        topic: 'A topic',
        canEditName: true,
        canEditTopic: true,
        canEditAvatar: false,
        canInvite: true,
        canChangeJoinRules: false,
        canChangePowerLevels: true,
        canEnableEncryption: false,
        isEncrypted: false,
        powerLevelsContent: {},
        participants: [],
        myPowerLevel: 100,
      );

      expect(perms.roomId, '!r:e.com');
      expect(perms.displayName, 'Test Room');
      expect(perms.topic, 'A topic');
      expect(perms.canEditName, isTrue);
      expect(perms.canChangePowerLevels, isTrue);
      expect(perms.myPowerLevel, 100);
    });

    test('equality is based on roomId', () {
      const a = KoheraRoomPermissions(
        roomId: '!r:e.com',
        canEditName: true,
        canEditTopic: false,
        canEditAvatar: false,
        canInvite: false,
        canChangeJoinRules: false,
        canChangePowerLevels: false,
        canEnableEncryption: false,
        isEncrypted: false,
        powerLevelsContent: {},
        participants: [],
        myPowerLevel: 0,
      );
      const b = KoheraRoomPermissions(
        roomId: '!r:e.com',
        canEditName: false,
        canEditTopic: true,
        canEditAvatar: true,
        canInvite: true,
        canChangeJoinRules: true,
        canChangePowerLevels: true,
        canEnableEncryption: true,
        isEncrypted: true,
        powerLevelsContent: {'invite': 50},
        participants: [
          KoheraRoomMember(
            userId: '@a:e.com',
            displayname: 'A',
            membership: 'join',
            powerLevel: 0,
          ),
        ],
        myPowerLevel: 100,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('copyWith preserves un-overridden fields', () {
      const perms = KoheraRoomPermissions(
        roomId: '!r:e.com',
        displayName: 'Room',
        topic: 'Topic',
        canEditName: true,
        canEditTopic: false,
        canEditAvatar: false,
        canInvite: false,
        canChangeJoinRules: false,
        canChangePowerLevels: true,
        canEnableEncryption: false,
        isEncrypted: false,
        powerLevelsContent: {},
        participants: [],
        myPowerLevel: 50,
      );

      final copy = perms.copyWith(isEncrypted: true);
      expect(copy.roomId, '!r:e.com');
      expect(copy.displayName, 'Room');
      expect(copy.canEditName, isTrue);
      expect(copy.isEncrypted, isTrue);
    });

    test('toString includes roomId', () {
      const perms = KoheraRoomPermissions(
        roomId: '!r:e.com',
        canEditName: false,
        canEditTopic: false,
        canEditAvatar: false,
        canInvite: false,
        canChangeJoinRules: false,
        canChangePowerLevels: false,
        canEnableEncryption: false,
        isEncrypted: false,
        powerLevelsContent: {},
        participants: [],
        myPowerLevel: 0,
      );
      expect(perms.toString(), contains('!r:e.com'));
    });
  });
}
