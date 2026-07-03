import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/sub_services/presence_service.dart';
import 'package:kohera/features/rooms/models/kohera_room_member.dart';
import 'package:kohera/features/rooms/models/room_role.dart';
import 'package:kohera/features/rooms/widgets/member_sheet_dialog.dart';
import 'package:kohera/features/rooms/widgets/room_members_section.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';

// ── Fakes ──────────────────────────────────────────────────────

class _NullAvatarResolver implements AvatarResolver {
  const _NullAvatarResolver();
  @override
  Future<AvatarThumbnail?> resolve(
    String? mxcUrl, {
    required double size,
  }) async => null;
}

class _NullPresence implements PresenceService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// ── Helpers ──────────────────────────────────────────────────

KoheraRoomMember _member({
  String userId = '@alice:example.com',
  String displayname = 'Alice',
  String? avatarUrl,
  String membership = 'join',
  int powerLevel = 0,
}) =>
    KoheraRoomMember(
      userId: userId,
      displayname: displayname,
      avatarUrl: avatarUrl,
      membership: membership,
      powerLevel: powerLevel,
    );

KoheraRoomMemberList _list(
  List<KoheraRoomMember> members, {
  bool complete = true,
  int count = 0,
}) =>
    KoheraRoomMemberList(
      members: members,
      participantListComplete: complete,
      memberCount: count,
    );

const _avatarResolver = _NullAvatarResolver();

PresenceService _nullPresence() => _NullPresence();

Widget _wrapSection(
  KoheraRoomMemberList members, {
  void Function(KoheraRoomMember)? onMemberTap,
}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RoomMembersSection(
            members: members,
            onMemberTap: onMemberTap ?? (_) {},
            avatarResolver: _avatarResolver,
            presence: _nullPresence(),
          ),
        ),
      ),
    );

Widget _wrapDialog(MemberSheetDialog dialog) => MaterialApp(
      home: Scaffold(
        body: Center(child: dialog),
      ),
    );

// ── RoomMembersSection tests ──────────────────────────────────

void main() {
  group('RoomMembersSection', () {
    testWidgets('shows nothing when empty', (tester) async {
      await tester.pumpWidget(_wrapSection(_list([])));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('No members'), findsNothing);
    });

    testWidgets('shows members after loading', (tester) async {
      await tester.pumpWidget(
        _wrapSection(
          _list([
            _member(userId: '@alice:e.com'),
            _member(displayname: 'Bob', userId: '@bob:e.com'),
          ]),
        ),
      );
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('shows only first 5 members with expand button',
        (tester) async {
      final members = List.generate(
        8,
        (i) => _member(
          displayname: 'User$i',
          userId: '@user$i:e.com',
        ),
      );
      await tester.pumpWidget(_wrapSection(_list(members)));
      await tester.pump();

      expect(find.text('Show all 8 members'), findsOneWidget);
      expect(find.text('User0'), findsOneWidget);
      expect(find.text('User4'), findsOneWidget);
      expect(find.text('User5'), findsNothing);
    });

    testWidgets('expand button shows all members', (tester) async {
      final members = List.generate(
        8,
        (i) => _member(
          displayname: 'User$i',
          userId: '@user$i:e.com',
        ),
      );
      await tester.pumpWidget(_wrapSection(_list(members)));
      await tester.pump();

      await tester.tap(find.text('Show all 8 members'));
      await tester.pump();

      expect(find.text('User5'), findsOneWidget);
      expect(find.text('User7'), findsOneWidget);
    });

    testWidgets('shows Admin badge for power level >= 100', (tester) async {
      await tester.pumpWidget(
        _wrapSection(
          _list([
            _member(powerLevel: 100),
          ]),
        ),
      );
      await tester.pump();

      expect(find.text('Admin'), findsOneWidget);
    });

    testWidgets('shows Mod badge for power level >= 50', (tester) async {
      await tester.pumpWidget(
        _wrapSection(
          _list([
            _member(displayname: 'Bob', powerLevel: 50),
          ]),
        ),
      );
      await tester.pump();

      expect(find.text('Mod'), findsOneWidget);
    });

    testWidgets('no badge for power level < 50', (tester) async {
      await tester.pumpWidget(
        _wrapSection(
          _list([
            _member(displayname: 'Carol'),
          ]),
        ),
      );
      await tester.pump();

      expect(find.text('Admin'), findsNothing);
      expect(find.text('Mod'), findsNothing);
    });

    testWidgets('search filters members by display name', (tester) async {
      final members = List.generate(
        8,
        (i) => _member(
          displayname: 'User$i',
          userId: '@user$i:e.com',
        ),
      );
      await tester.pumpWidget(_wrapSection(_list(members)));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'user3');
      await tester.pump();

      expect(find.text('User3'), findsOneWidget);
      expect(find.text('User0'), findsNothing);
    });

    testWidgets('search field hidden when 5 or fewer members',
        (tester) async {
      await tester.pumpWidget(
        _wrapSection(
          _list([
            _member(),
            _member(displayname: 'Bob', userId: '@bob:e.com'),
          ]),
        ),
      );
      await tester.pump();

      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('tapping member calls onMemberTap', (tester) async {
      KoheraRoomMember? tapped;
      final member = _member(userId: '@alice:e.com');
      await tester.pumpWidget(
        _wrapSection(
          _list([member]),
          onMemberTap: (m) => tapped = m,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Alice'));
      await tester.pump();

      expect(tapped, isNotNull);
      expect(tapped?.userId, '@alice:e.com');
    });
  });

  // ── MemberSheetDialog tests ──────────────────────────────────

  group('MemberSheetDialog', () {
    testWidgets('shows member info', (tester) async {
      await tester.pumpWidget(
        _wrapDialog(
          MemberSheetDialog(
            member: _member(userId: '@alice:e.com'),
            isMe: false,
            ownLevel: 100,
            canChangeRole: false,
            canKick: false,
            canBan: false,
            avatarResolver: _avatarResolver,
            presence: _nullPresence(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('@alice:e.com'), findsOneWidget);
    });

    testWidgets('shows role dropdown when canChangeRole', (tester) async {
      await tester.pumpWidget(
        _wrapDialog(
          MemberSheetDialog(
            member: _member(displayname: 'Bob'),
            isMe: false,
            ownLevel: 100,
            canChangeRole: true,
            canKick: false,
            canBan: false,
            avatarResolver: _avatarResolver,
            presence: _nullPresence(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButton<RoomRole>), findsOneWidget);
    });

    testWidgets('hides role dropdown when isMe', (tester) async {
      await tester.pumpWidget(
        _wrapDialog(
          MemberSheetDialog(
            member: _member(displayname: 'Me', powerLevel: 100),
            isMe: true,
            ownLevel: 100,
            canChangeRole: false,
            canKick: false,
            canBan: false,
            avatarResolver: _avatarResolver,
            presence: _nullPresence(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButton<RoomRole>), findsNothing);
    });

    testWidgets('shows kick action when canKick', (tester) async {
      await tester.pumpWidget(
        _wrapDialog(
          MemberSheetDialog(
            member: _member(displayname: 'Bob'),
            isMe: false,
            ownLevel: 100,
            canChangeRole: false,
            canKick: true,
            canBan: false,
            avatarResolver: _avatarResolver,
            presence: _nullPresence(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kick'), findsOneWidget);
    });

    testWidgets('hides kick action when not canKick', (tester) async {
      await tester.pumpWidget(
        _wrapDialog(
          MemberSheetDialog(
            member: _member(displayname: 'Bob'),
            isMe: false,
            ownLevel: 100,
            canChangeRole: false,
            canKick: false,
            canBan: false,
            avatarResolver: _avatarResolver,
            presence: _nullPresence(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kick'), findsNothing);
    });

    testWidgets('shows ban action when canBan', (tester) async {
      await tester.pumpWidget(
        _wrapDialog(
          MemberSheetDialog(
            member: _member(displayname: 'Bob'),
            isMe: false,
            ownLevel: 100,
            canChangeRole: false,
            canKick: false,
            canBan: true,
            avatarResolver: _avatarResolver,
            presence: _nullPresence(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ban'), findsOneWidget);
    });

    testWidgets('shows unban action for banned member', (tester) async {
      await tester.pumpWidget(
        _wrapDialog(
          MemberSheetDialog(
            member: _member(displayname: 'Bob', membership: 'ban'),
            isMe: false,
            ownLevel: 100,
            canChangeRole: false,
            canKick: false,
            canBan: true,
            avatarResolver: _avatarResolver,
            presence: _nullPresence(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Unban'), findsOneWidget);
      expect(find.text('Ban'), findsNothing);
    });

    testWidgets('shows Send message when onStartDm provided', (tester) async {
      await tester.pumpWidget(
        _wrapDialog(
          MemberSheetDialog(
            member: _member(displayname: 'Bob'),
            isMe: false,
            ownLevel: 100,
            canChangeRole: false,
            canKick: false,
            canBan: false,
            avatarResolver: _avatarResolver,
            presence: _nullPresence(),
            onStartDm: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Send message'), findsOneWidget);
    });

    testWidgets('hides Send message when isMe', (tester) async {
      await tester.pumpWidget(
        _wrapDialog(
          MemberSheetDialog(
            member: _member(displayname: 'Me'),
            isMe: true,
            ownLevel: 100,
            canChangeRole: false,
            canKick: false,
            canBan: false,
            avatarResolver: _avatarResolver,
            presence: _nullPresence(),
            onStartDm: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Send message'), findsNothing);
    });

    testWidgets('kick calls onKick callback', (tester) async {
      String? kickReason;
      await tester.pumpWidget(
        _wrapDialog(
          MemberSheetDialog(
            member: _member(displayname: 'Bob', userId: '@bob:e.com'),
            isMe: false,
            ownLevel: 100,
            canChangeRole: false,
            canKick: true,
            canBan: false,
            avatarResolver: _avatarResolver,
            presence: _nullPresence(),
            onKick: (reason) async {
              kickReason = reason;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kick'));
      await tester.pumpAndSettle();

      expect(find.text('Kick member?'), findsOneWidget);

      await tester.tap(find.text('Kick').last);
      await tester.pumpAndSettle();

      expect(kickReason, isNull);
    });

    testWidgets('ban calls onBan callback', (tester) async {
      String? banReason;
      await tester.pumpWidget(
        _wrapDialog(
          MemberSheetDialog(
            member: _member(displayname: 'Bob'),
            isMe: false,
            ownLevel: 100,
            canChangeRole: false,
            canKick: false,
            canBan: true,
            avatarResolver: _avatarResolver,
            presence: _nullPresence(),
            onBan: (reason) async {
              banReason = reason;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ban'));
      await tester.pumpAndSettle();

      expect(find.text('Ban member?'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Spamming');
      await tester.tap(find.text('Ban').last);
      await tester.pumpAndSettle();

      expect(banReason, 'Spamming');
    });

    testWidgets('role change calls onRoleChange callback', (tester) async {
      int? newLevel;
      await tester.pumpWidget(
        _wrapDialog(
          MemberSheetDialog(
            member: _member(displayname: 'Bob'),
            isMe: false,
            ownLevel: 100,
            canChangeRole: true,
            canKick: false,
            canBan: false,
            avatarResolver: _avatarResolver,
            presence: _nullPresence(),
            onRoleChange: (level) async {
              newLevel = level;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<RoomRole>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Moderator').last);
      await tester.pumpAndSettle();

      expect(newLevel, 50);
    });

    testWidgets('shows error on kick failure', (tester) async {
      await tester.pumpWidget(
        _wrapDialog(
          MemberSheetDialog(
            member: _member(displayname: 'Bob'),
            isMe: false,
            ownLevel: 100,
            canChangeRole: false,
            canKick: true,
            canBan: false,
            avatarResolver: _avatarResolver,
            presence: _nullPresence(),
            onKick: (reason) async => throw Exception('Permission denied'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kick'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kick').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Permission denied'), findsOneWidget);
    });

    testWidgets('shows power level description', (tester) async {
      await tester.pumpWidget(
        _wrapDialog(
          MemberSheetDialog(
            member: _member(powerLevel: 100),
            isMe: false,
            ownLevel: 100,
            canChangeRole: false,
            canKick: false,
            canBan: false,
            avatarResolver: _avatarResolver,
            presence: _nullPresence(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Admin (power level 100)'), findsOneWidget);
    });
  });
}
