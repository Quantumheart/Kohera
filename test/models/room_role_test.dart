import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/rooms/models/room_role.dart';

void main() {
  group('RoomRole', () {
    group('fromPowerLevel', () {
      test('maps 100 to admin', () {
        final role = RoomRole.fromPowerLevel(100);
        expect(role, isA<RoomRole>());
        expect(role.toPowerLevel(), equals(100));
        expect(role.label, equals('Admin'));
      });

      test('maps 50 to moderator', () {
        final role = RoomRole.fromPowerLevel(50);
        expect(role.toPowerLevel(), equals(50));
        expect(role.label, equals('Moderator'));
      });

      test('maps 0 to member', () {
        final role = RoomRole.fromPowerLevel(0);
        expect(role.toPowerLevel(), equals(0));
        expect(role.label, equals('Member'));
      });

      test('maps non-standard levels to custom', () {
        final role = RoomRole.fromPowerLevel(47);
        expect(role.toPowerLevel(), equals(47));
        expect(role.label, equals('Custom (47)'));
      });

      test('handles negative power levels', () {
        final role = RoomRole.fromPowerLevel(-10);
        expect(role.toPowerLevel(), equals(-10));
        expect(role.label, equals('Custom (-10)'));
      });

      test('handles large power levels', () {
        final role = RoomRole.fromPowerLevel(9999);
        expect(role.toPowerLevel(), equals(9999));
        expect(role.label, equals('Custom (9999)'));
      });
    });

    group('direct construction', () {
      test('can create admin role directly', () {
        const role = RoomRole.admin();
        expect(role.toPowerLevel(), equals(100));
        expect(role.label, equals('Admin'));
      });

      test('can create moderator role directly', () {
        const role = RoomRole.moderator();
        expect(role.toPowerLevel(), equals(50));
        expect(role.label, equals('Moderator'));
      });

      test('can create member role directly', () {
        const role = RoomRole.member();
        expect(role.toPowerLevel(), equals(0));
        expect(role.label, equals('Member'));
      });

      test('can create custom role directly', () {
        const role = RoomRole.custom(75);
        expect(role.toPowerLevel(), equals(75));
        expect(role.label, equals('Custom (75)'));
      });
    });

    group('round-trip conversions', () {
      test('admin round-trips', () {
        const admin = RoomRole.admin();
        final level = admin.toPowerLevel();
        final reconstructed = RoomRole.fromPowerLevel(level);
        expect(reconstructed.toPowerLevel(), equals(admin.toPowerLevel()));
        expect(reconstructed.label, equals(admin.label));
      });

      test('moderator round-trips', () {
        const moderator = RoomRole.moderator();
        final level = moderator.toPowerLevel();
        final reconstructed = RoomRole.fromPowerLevel(level);
        expect(reconstructed.toPowerLevel(), equals(moderator.toPowerLevel()));
        expect(reconstructed.label, equals(moderator.label));
      });

      test('member round-trips', () {
        const member = RoomRole.member();
        final level = member.toPowerLevel();
        final reconstructed = RoomRole.fromPowerLevel(level);
        expect(reconstructed.toPowerLevel(), equals(member.toPowerLevel()));
        expect(reconstructed.label, equals(member.label));
      });

      test('custom levels round-trip', () {
        const custom = RoomRole.custom(42);
        final level = custom.toPowerLevel();
        final reconstructed = RoomRole.fromPowerLevel(level);
        expect(reconstructed.toPowerLevel(), equals(custom.toPowerLevel()));
        expect(reconstructed.label, equals(custom.label));
      });
    });

    group('descriptions', () {
      test('admin has appropriate description', () {
        expect(
          const RoomRole.admin().description,
          equals('Full room control and management'),
        );
      });

      test('moderator has appropriate description', () {
        expect(
          const RoomRole.moderator().description,
          equals('Can moderate members and pin messages'),
        );
      });

      test('member has appropriate description', () {
        expect(
          const RoomRole.member().description,
          equals('Can send messages and react'),
        );
      });

      test('custom has generic description', () {
        expect(
          const RoomRole.custom(99).description,
          equals('Custom power level'),
        );
      });
    });

    group('canAssignRole - admin hierarchy', () {
      test('admin can assign admin to anyone below them', () {
        expect(
          RoomRole.canAssignRole(
            target: const RoomRole.admin(),
            ownLevel: 100,
            targetCurrentLevel: 50,
          ),
          isTrue,
        );
      });

      test('admin can assign moderator to anyone below them', () {
        expect(
          RoomRole.canAssignRole(
            target: const RoomRole.moderator(),
            ownLevel: 100,
            targetCurrentLevel: 0,
          ),
          isTrue,
        );
      });

      test('admin can assign member to anyone below them', () {
        expect(
          RoomRole.canAssignRole(
            target: const RoomRole.member(),
            ownLevel: 100,
            targetCurrentLevel: 50,
          ),
          isTrue,
        );
      });

      test('admin can assign custom roles', () {
        expect(
          RoomRole.canAssignRole(
            target: const RoomRole.custom(75),
            ownLevel: 100,
            targetCurrentLevel: 25,
          ),
          isTrue,
        );
      });

      test('admin cannot assign role to someone at their level', () {
        expect(
          RoomRole.canAssignRole(
            target: const RoomRole.moderator(),
            ownLevel: 100,
            targetCurrentLevel: 100,
          ),
          isFalse,
        );
      });

      test('admin cannot assign role to someone above their level', () {
        expect(
          RoomRole.canAssignRole(
            target: const RoomRole.admin(),
            ownLevel: 100,
            targetCurrentLevel: 150,
          ),
          isFalse,
        );
      });
    });

    group('canAssignRole - moderator hierarchy', () {
      test('moderator can only assign member role', () {
        expect(
          RoomRole.canAssignRole(
            target: const RoomRole.member(),
            ownLevel: 50,
            targetCurrentLevel: 0,
          ),
          isTrue,
        );
      });

      test('moderator cannot assign admin', () {
        expect(
          RoomRole.canAssignRole(
            target: const RoomRole.admin(),
            ownLevel: 50,
            targetCurrentLevel: 0,
          ),
          isFalse,
        );
      });

      test('moderator can assign moderator role to users below them', () {
        expect(
          RoomRole.canAssignRole(
            target: const RoomRole.moderator(),
            ownLevel: 50,
            targetCurrentLevel: 0,
          ),
          isTrue,
        );
      });

      test('moderator cannot assign role to someone at their level', () {
        expect(
          RoomRole.canAssignRole(
            target: const RoomRole.member(),
            ownLevel: 50,
            targetCurrentLevel: 50,
          ),
          isFalse,
        );
      });

      test('moderator cannot assign role to anyone above them', () {
        expect(
          RoomRole.canAssignRole(
            target: const RoomRole.member(),
            ownLevel: 50,
            targetCurrentLevel: 100,
          ),
          isFalse,
        );
      });

      test('moderator can assign custom role below their level', () {
        expect(
          RoomRole.canAssignRole(
            target: const RoomRole.custom(25),
            ownLevel: 50,
            targetCurrentLevel: 10,
          ),
          isTrue,
        );
      });

      test('moderator can assign custom role equal to their level to users below them', () {
        expect(
          RoomRole.canAssignRole(
            target: const RoomRole.custom(50),
            ownLevel: 50,
            targetCurrentLevel: 10,
          ),
          isTrue,
        );
      });

      test('moderator cannot assign custom role above their level', () {
        expect(
          RoomRole.canAssignRole(
            target: const RoomRole.custom(75),
            ownLevel: 50,
            targetCurrentLevel: 10,
          ),
          isFalse,
        );
      });
    });

    group('canAssignRole - member hierarchy', () {
      test('member cannot assign any role', () {
        expect(
          RoomRole.canAssignRole(
            target: const RoomRole.member(),
            ownLevel: 0,
            targetCurrentLevel: 0,
          ),
          isFalse,
        );
      });

      test('member cannot assign admin', () {
        expect(
          RoomRole.canAssignRole(
            target: const RoomRole.admin(),
            ownLevel: 0,
            targetCurrentLevel: 0,
          ),
          isFalse,
        );
      });
    });

    group('canAssignRole - edge cases', () {
      test('cannot modify self at same level', () {
        expect(
          RoomRole.canAssignRole(
            target: const RoomRole.moderator(),
            ownLevel: 50,
            targetCurrentLevel: 50,
          ),
          isFalse,
        );
      });

      test('cannot modify user at same level even with higher target role', () {
        expect(
          RoomRole.canAssignRole(
            target: const RoomRole.admin(),
            ownLevel: 100,
            targetCurrentLevel: 100,
          ),
          isFalse,
        );
      });

      test('room creator (level 100) can demote everyone else', () {
        expect(
          RoomRole.canAssignRole(
            target: const RoomRole.member(),
            ownLevel: 100,
            targetCurrentLevel: 100,
          ),
          isFalse, // Cannot modify user at same level
        );
        expect(
          RoomRole.canAssignRole(
            target: const RoomRole.member(),
            ownLevel: 100,
            targetCurrentLevel: 99,
          ),
          isTrue, // Can modify users below them
        );
      });

      test('handles zero and negative power levels correctly', () {
        expect(
          RoomRole.canAssignRole(
            target: const RoomRole.custom(-5),
            ownLevel: 0,
            targetCurrentLevel: -10,
          ),
          isTrue,
        );
      });
    });

    group('pattern matching', () {
      test('map works for admin', () {
        const admin = RoomRole.admin();
        final result = admin.map(
          admin: (_) => 'is_admin',
          moderator: (_) => 'is_moderator',
          member: (_) => 'is_member',
          custom: (_) => 'is_custom',
        );
        expect(result, equals('is_admin'));
      });

      test('map works for custom', () {
        const custom = RoomRole.custom(42);
        final result = custom.map(
          admin: (_) => 'is_admin',
          moderator: (_) => 'is_moderator',
          member: (_) => 'is_member',
          custom: (_) => 'is_custom',
        );
        expect(result, equals('is_custom'));
      });

      test('maybeMap handles null cases', () {
        const member = RoomRole.member();
        final result = member.maybeMap(
          admin: (_) => 'admin_case',
          orElse: 'other_case',
        );
        expect(result, equals('other_case'));
      });

      test('maybeMap returns mapped value when present', () {
        const member = RoomRole.member();
        final result = member.maybeMap(
          member: (_) => 'member_case',
          orElse: 'other_case',
        );
        expect(result, equals('member_case'));
      });
    });

    group('equality and hashing', () {
      test('admin roles are equal', () {
        expect(const RoomRole.admin(), equals(const RoomRole.admin()));
      });

      test('moderator roles are equal', () {
        expect(const RoomRole.moderator(), equals(const RoomRole.moderator()));
      });

      test('member roles are equal', () {
        expect(const RoomRole.member(), equals(const RoomRole.member()));
      });

      test('custom roles with same value are equal', () {
        expect(
          const RoomRole.custom(42),
          equals(const RoomRole.custom(42)),
        );
      });

      test('custom roles with different values are not equal', () {
        expect(
          const RoomRole.custom(42),
          isNot(equals(const RoomRole.custom(43))),
        );
      });

      test('different role types are not equal', () {
        expect(
          const RoomRole.admin(),
          isNot(equals(const RoomRole.custom(100))),
        );
      });

      test('admin roles have same hash', () {
        expect(
          const RoomRole.admin().hashCode,
          equals(const RoomRole.admin().hashCode),
        );
      });

      test('custom roles with same value have same hash', () {
        expect(
          const RoomRole.custom(42).hashCode,
          equals(const RoomRole.custom(42).hashCode),
        );
      });
    });

    group('toString', () {
      test('admin toString returns label', () {
        expect(const RoomRole.admin().toString(), equals('Admin'));
      });

      test('moderator toString returns label', () {
        expect(const RoomRole.moderator().toString(), equals('Moderator'));
      });

      test('member toString returns label', () {
        expect(const RoomRole.member().toString(), equals('Member'));
      });

      test('custom toString returns label with value', () {
        expect(const RoomRole.custom(47).toString(), equals('Custom (47)'));
      });
    });
  });
}
