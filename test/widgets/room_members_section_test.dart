import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/rooms/models/room_role.dart';
import 'package:kohera/features/rooms/widgets/room_members_section.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<MatrixService>(),
  MockSpec<Room>(),
  MockSpec<User>(),
])
import 'room_members_section_test.mocks.dart';

MockUser _makeUser(String id, String displayName, {Room? room}) {
  final user = MockUser();
  when(user.id).thenReturn(id);
  when(user.displayName).thenReturn(displayName);
  when(user.room).thenReturn(room ?? MockRoom());
  when(user.membership).thenReturn(Membership.join);
  return user;
}

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrixService;
  late MockRoom mockRoom;

  setUp(() {
    mockClient = MockClient();
    mockMatrixService = MockMatrixService();
    mockRoom = MockRoom();

    when(mockMatrixService.client).thenReturn(mockClient);
    when(mockRoom.id).thenReturn('!room:example.com');
    when(mockRoom.client).thenReturn(mockClient);
    when(mockRoom.summary).thenReturn(RoomSummary.fromJson({
      'm.joined_member_count': 3,
      'm.invited_member_count': 0,
    }),);
    when(mockRoom.getPowerLevelByUserId(any)).thenReturn(0);
    when(mockRoom.canKick).thenReturn(false);
    when(mockRoom.canBan).thenReturn(false);
    when(mockClient.userID).thenReturn('@me:example.com');
  });

  Widget buildTestWidget() {
    return MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: ChangeNotifierProvider<MatrixService>.value(
        value: mockMatrixService,
        child: Scaffold(
          body: SingleChildScrollView(
            child: RoomMembersSection(room: mockRoom),
          ),
        ),
      ),
    );
  }

  group('RoomMembersSection', () {
    testWidgets('shows loading indicator while fetching members',
        (tester) async {
      final completer = Completer<List<User>>();
      when(mockRoom.requestParticipants(any))
          .thenAnswer((_) => completer.future);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('MEMBERS'), findsOneWidget);

      // Complete the future to avoid pending timer issues
      completer.complete([]);
      await tester.pumpAndSettle();
    });

    testWidgets('shows members after loading', (tester) async {
      final alice = _makeUser('@alice:example.com', 'Alice', room: mockRoom);
      final bob = _makeUser('@bob:example.com', 'Bob', room: mockRoom);

      when(mockRoom.requestParticipants(any))
          .thenAnswer((_) async => [alice, bob]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('shows only first 5 members with expand button',
        (tester) async {
      final users = List.generate(
        8,
        (i) => _makeUser('@user$i:example.com', 'User $i', room: mockRoom),
      );

      when(mockRoom.requestParticipants(any)).thenAnswer((_) async => users);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // First 5 should be visible
      for (var i = 0; i < 5; i++) {
        expect(find.text('User $i'), findsOneWidget);
      }
      // 6th should not be visible yet
      expect(find.text('User 5'), findsNothing);

      // Expand button should show
      expect(find.text('Show all 8 members'), findsOneWidget);
    });

    testWidgets('expand button shows all members', (tester) async {
      final users = List.generate(
        8,
        (i) => _makeUser('@user$i:example.com', 'User $i', room: mockRoom),
      );

      when(mockRoom.requestParticipants(any)).thenAnswer((_) async => users);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show all 8 members'));
      await tester.pumpAndSettle();

      // All 8 should be visible now
      for (var i = 0; i < 8; i++) {
        expect(find.text('User $i'), findsOneWidget);
      }
      expect(find.text('Show all 8 members'), findsNothing);
    });

    testWidgets('shows Admin badge for power level >= 100', (tester) async {
      final admin = _makeUser('@admin:example.com', 'Admin User', room: mockRoom);
      when(mockRoom.getPowerLevelByUserId('@admin:example.com')).thenReturn(100);
      when(mockRoom.requestParticipants(any)).thenAnswer((_) async => [admin]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Admin'), findsOneWidget);
    });

    testWidgets('shows Mod badge for power level >= 50', (tester) async {
      final mod = _makeUser('@mod:example.com', 'Mod User', room: mockRoom);
      when(mockRoom.getPowerLevelByUserId('@mod:example.com')).thenReturn(50);
      when(mockRoom.requestParticipants(any)).thenAnswer((_) async => [mod]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Mod'), findsOneWidget);
    });

    testWidgets('search filters members by display name and MXID',
        (tester) async {
      final users = [
        _makeUser('@alice:example.com', 'Alice', room: mockRoom),
        _makeUser('@bob:example.com', 'Bob', room: mockRoom),
        _makeUser('@charlie:example.com', 'Charlie', room: mockRoom),
        _makeUser('@dave:example.com', 'Dave', room: mockRoom),
        _makeUser('@eve:example.com', 'Eve', room: mockRoom),
        _makeUser('@frank:example.com', 'Frank', room: mockRoom),
      ];
      when(mockRoom.requestParticipants(any)).thenAnswer((_) async => users);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'ali');
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);

      await tester.enterText(find.byType(TextField), '@bob');
      await tester.pumpAndSettle();
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.textContaining('No members match'), findsOneWidget);
    });

    testWidgets('search field hidden when 5 or fewer members', (tester) async {
      final users = List.generate(
        5,
        (i) => _makeUser('@user$i:example.com', 'User $i', room: mockRoom),
      );
      when(mockRoom.requestParticipants(any)).thenAnswer((_) async => users);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Search members'), findsNothing);
      expect(find.byIcon(Icons.search), findsNothing);
    });

    testWidgets('search clear button restores full list', (tester) async {
      final users = List.generate(
        6,
        (i) => _makeUser('@user$i:example.com', 'User $i', room: mockRoom),
      );
      when(mockRoom.requestParticipants(any)).thenAnswer((_) async => users);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'user0');
      await tester.pumpAndSettle();
      expect(find.text('User 0'), findsOneWidget);
      expect(find.text('User 1'), findsNothing);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      for (var i = 0; i < 5; i++) {
        expect(find.text('User $i'), findsOneWidget);
      }
      expect(find.text('Show all 6 members'), findsOneWidget);
    });

    testWidgets('tapping member opens SimpleDialog with member info',
        (tester) async {
      final alice = _makeUser('@alice:example.com', 'Alice', room: mockRoom);
      when(mockRoom.requestParticipants(any))
          .thenAnswer((_) async => [alice]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      expect(find.byType(SimpleDialog), findsOneWidget);
      expect(find.text('@alice:example.com'), findsWidgets);
      // 'Member' appears in both the title description and the dropdown value.
      expect(find.text('Member'), findsWidgets);
    });

    testWidgets('kick action prompts for reason and forwards it to client.kick',
        (tester) async {
      when(mockRoom.getPowerLevelByUserId('@me:example.com')).thenReturn(50);
      final alice = _makeUser('@alice:example.com', 'Alice', room: mockRoom);
      when(mockRoom.canKick).thenReturn(true);
      when(mockRoom.requestParticipants(any))
          .thenAnswer((_) async => [alice]);
      when(mockClient.kick(any, any, reason: anyNamed('reason')))
          .thenAnswer((_) async {});

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(SimpleDialogOption, 'Kick'));
      await tester.pumpAndSettle();

      expect(find.text('Kick member?'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'spamming');
      await tester.tap(find.widgetWithText(FilledButton, 'Kick'));
      await tester.pumpAndSettle();

      verify(mockClient.kick(
        '!room:example.com',
        '@alice:example.com',
        reason: 'spamming',
      ),).called(1);
    });

    testWidgets('kick with empty reason sends null reason', (tester) async {
      when(mockRoom.getPowerLevelByUserId('@me:example.com')).thenReturn(50);
      final alice = _makeUser('@alice:example.com', 'Alice', room: mockRoom);
      when(mockRoom.canKick).thenReturn(true);
      when(mockRoom.requestParticipants(any))
          .thenAnswer((_) async => [alice]);
      when(mockClient.kick(any, any, reason: anyNamed('reason')))
          .thenAnswer((_) async {});

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SimpleDialogOption, 'Kick'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Kick'));
      await tester.pumpAndSettle();

      verify(mockClient.kick(
        '!room:example.com',
        '@alice:example.com',
        reason: argThat(isNull, named: 'reason'),
      ),).called(1);
    });

    testWidgets('cancelling kick reason dialog does not call client.kick',
        (tester) async {
      when(mockRoom.getPowerLevelByUserId('@me:example.com')).thenReturn(50);
      final alice = _makeUser('@alice:example.com', 'Alice', room: mockRoom);
      when(mockRoom.canKick).thenReturn(true);
      when(mockRoom.requestParticipants(any))
          .thenAnswer((_) async => [alice]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SimpleDialogOption, 'Kick'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      verifyNever(mockClient.kick(any, any, reason: anyNamed('reason')));
    });

    testWidgets('ban action prompts for reason and forwards it to client.ban',
        (tester) async {
      when(mockRoom.getPowerLevelByUserId('@me:example.com')).thenReturn(50);
      final alice = _makeUser('@alice:example.com', 'Alice', room: mockRoom);
      when(mockRoom.canBan).thenReturn(true);
      when(mockRoom.requestParticipants(any))
          .thenAnswer((_) async => [alice]);
      when(mockClient.ban(any, any, reason: anyNamed('reason')))
          .thenAnswer((_) async {});

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SimpleDialogOption, 'Ban'));
      await tester.pumpAndSettle();

      expect(find.text('Ban member?'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'abuse');
      await tester.tap(find.widgetWithText(FilledButton, 'Ban'));
      await tester.pumpAndSettle();

      verify(mockClient.ban(
        '!room:example.com',
        '@alice:example.com',
        reason: 'abuse',
      ),).called(1);
    });

    testWidgets('kick and ban actions hidden when permissions are missing',
        (tester) async {
      final alice = _makeUser('@alice:example.com', 'Alice', room: mockRoom);
      when(mockRoom.canKick).thenReturn(false);
      when(mockRoom.canBan).thenReturn(false);
      when(mockRoom.requestParticipants(any))
          .thenAnswer((_) async => [alice]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(SimpleDialogOption, 'Kick'), findsNothing);
      expect(find.widgetWithText(SimpleDialogOption, 'Ban'), findsNothing);
    });

    testWidgets('kick and ban hidden when target power level >= viewer level',
        (tester) async {
      when(mockRoom.getPowerLevelByUserId('@me:example.com')).thenReturn(50);
      when(mockRoom.getPowerLevelByUserId('@alice:example.com')).thenReturn(50);
      final alice = _makeUser('@alice:example.com', 'Alice', room: mockRoom);
      when(mockRoom.canKick).thenReturn(true);
      when(mockRoom.canBan).thenReturn(true);
      when(mockRoom.requestParticipants(any)).thenAnswer((_) async => [alice]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(SimpleDialogOption, 'Kick'), findsNothing);
      expect(find.widgetWithText(SimpleDialogOption, 'Ban'), findsNothing);
    });

    testWidgets('ban dialog shows correct wording', (tester) async {
      when(mockRoom.getPowerLevelByUserId('@me:example.com')).thenReturn(50);
      final alice = _makeUser('@alice:example.com', 'Alice', room: mockRoom);
      when(mockRoom.canBan).thenReturn(true);
      when(mockRoom.requestParticipants(any)).thenAnswer((_) async => [alice]);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SimpleDialogOption, 'Ban'));
      await tester.pumpAndSettle();

      expect(find.textContaining("won't be able to rejoin"), findsOneWidget);
    });

    testWidgets('unban shown for banned user and calls client.unban',
        (tester) async {
      when(mockRoom.getPowerLevelByUserId('@me:example.com')).thenReturn(50);
      final alice = _makeUser('@alice:example.com', 'Alice', room: mockRoom);
      when(alice.membership).thenReturn(Membership.ban);
      when(mockRoom.canBan).thenReturn(true);
      when(mockRoom.requestParticipants(any)).thenAnswer((_) async => [alice]);
      when(mockClient.unban(any, any)).thenAnswer((_) async {});

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(SimpleDialogOption, 'Ban'), findsNothing);
      expect(find.widgetWithText(SimpleDialogOption, 'Unban'), findsOneWidget);

      await tester.tap(find.widgetWithText(SimpleDialogOption, 'Unban'));
      await tester.pumpAndSettle();

      expect(find.text('Unban member?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Unban'));
      await tester.pumpAndSettle();

      verify(mockClient.unban('!room:example.com', '@alice:example.com'))
          .called(1);
    });

    testWidgets('kick error shown inline without dismissing sheet',
        (tester) async {
      when(mockRoom.getPowerLevelByUserId('@me:example.com')).thenReturn(50);
      final alice = _makeUser('@alice:example.com', 'Alice', room: mockRoom);
      when(mockRoom.canKick).thenReturn(true);
      when(mockRoom.requestParticipants(any)).thenAnswer((_) async => [alice]);
      when(mockClient.kick(any, any, reason: anyNamed('reason')))
          .thenThrow(
        MatrixException.fromJson({
          'errcode': 'M_FORBIDDEN',
          'error': 'You do not have permission',
        }),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SimpleDialogOption, 'Kick'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Kick'));
      await tester.pumpAndSettle();

      // Sheet still open (Alice appears in tile + sheet title), error displayed inline.
      expect(find.text('Alice'), findsWidgets);
      expect(find.textContaining('permission'), findsOneWidget);
    });

    group('role dropdown', () {
      testWidgets('shows dropdown with current role for a member', (tester) async {
        final alice = _makeUser('@alice:example.com', 'Alice', room: mockRoom);
        when(mockRoom.getPowerLevelByUserId('@alice:example.com')).thenReturn(0);
        when(mockRoom.requestParticipants(any)).thenAnswer((_) async => [alice]);

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Alice'));
        await tester.pumpAndSettle();

        expect(find.byType(DropdownButton<RoomRole>), findsOneWidget);
        // 'Member' appears in the title description and the dropdown value.
        expect(find.text('Member'), findsWidgets);
      });

      testWidgets('shows dropdown with current role for a moderator', (tester) async {
        final alice = _makeUser('@alice:example.com', 'Alice', room: mockRoom);
        when(mockRoom.getPowerLevelByUserId('@alice:example.com')).thenReturn(50);
        when(mockRoom.requestParticipants(any)).thenAnswer((_) async => [alice]);

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Alice'));
        await tester.pumpAndSettle();

        expect(find.text('Moderator'), findsWidgets);
      });

      testWidgets('dropdown is disabled when viewer cannot change power levels',
          (tester) async {
        final alice = _makeUser('@alice:example.com', 'Alice', room: mockRoom);
        when(mockRoom.getPowerLevelByUserId('@alice:example.com')).thenReturn(0);
        when(mockRoom.canChangePowerLevel).thenReturn(false);
        when(mockRoom.requestParticipants(any)).thenAnswer((_) async => [alice]);

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Alice'));
        await tester.pumpAndSettle();

        final dropdown = tester.widget<DropdownButton<RoomRole>>(
          find.byType(DropdownButton<RoomRole>),
        );
        expect(dropdown.onChanged, isNull);
      });

      testWidgets('dropdown is disabled when target is at or above viewer level',
          (tester) async {
        // Viewer is moderator (50), target is also moderator (50).
        when(mockClient.userID).thenReturn('@me:example.com');
        when(mockRoom.getPowerLevelByUserId('@me:example.com')).thenReturn(50);
        final alice = _makeUser('@alice:example.com', 'Alice', room: mockRoom);
        when(mockRoom.getPowerLevelByUserId('@alice:example.com')).thenReturn(50);
        when(mockRoom.canChangePowerLevel).thenReturn(true);
        when(mockRoom.requestParticipants(any)).thenAnswer((_) async => [alice]);

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Alice'));
        await tester.pumpAndSettle();

        final dropdown = tester.widget<DropdownButton<RoomRole>>(
          find.byType(DropdownButton<RoomRole>),
        );
        expect(dropdown.onChanged, isNull);
      });

      testWidgets('selecting a role calls setRoomStateWithKey with correct patch',
          (tester) async {
        // Viewer is admin (100), target Alice is member (0).
        when(mockClient.userID).thenReturn('@me:example.com');
        when(mockRoom.getPowerLevelByUserId('@me:example.com')).thenReturn(100);
        final alice = _makeUser('@alice:example.com', 'Alice', room: mockRoom);
        when(mockRoom.getPowerLevelByUserId('@alice:example.com')).thenReturn(0);
        when(mockRoom.canChangePowerLevel).thenReturn(true);
        when(mockRoom.getState(EventTypes.RoomPowerLevels)).thenReturn(null);
        when(mockRoom.requestParticipants(any)).thenAnswer((_) async => [alice]);
        when(mockClient.setRoomStateWithKey(any, any, any, any))
            .thenAnswer((_) async => r'$eventId');

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Alice'));
        await tester.pumpAndSettle();

        // Open dropdown and select Moderator.
        await tester.tap(find.byType(DropdownButton<RoomRole>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Moderator').last);
        await tester.pumpAndSettle();

        verify(mockClient.setRoomStateWithKey(
          '!room:example.com',
          EventTypes.RoomPowerLevels,
          '',
          argThat(predicate<Map<String, Object?>>(
            (m) {
              final users = m['users'] as Map<String, Object?>?;
              return users?['@alice:example.com'] == 50;
            },
            'contains users.@alice:example.com == 50',
          ),),
        ),).called(1);
      });

      testWidgets('shows confirmation dialog before demoting an admin',
          (tester) async {
        when(mockClient.userID).thenReturn('@me:example.com');
        // Viewer at 150 so they outrank Alice at 100 and canChangeRole is true.
        when(mockRoom.getPowerLevelByUserId('@me:example.com')).thenReturn(150);
        final alice = _makeUser('@alice:example.com', 'Alice', room: mockRoom);
        when(mockRoom.getPowerLevelByUserId('@alice:example.com')).thenReturn(100);
        when(mockRoom.canChangePowerLevel).thenReturn(true);
        when(mockRoom.getState(EventTypes.RoomPowerLevels)).thenReturn(null);
        when(mockRoom.requestParticipants(any)).thenAnswer((_) async => [alice]);
        when(mockClient.setRoomStateWithKey(any, any, any, any))
            .thenAnswer((_) async => r'$eventId');

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Alice'));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(DropdownButton<RoomRole>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Member').last);
        await tester.pumpAndSettle();

        expect(find.text('Demote admin?'), findsOneWidget);
        verifyNever(mockClient.setRoomStateWithKey(any, any, any, any));
      });

      testWidgets('cancelling demotion confirm does not call setRoomStateWithKey',
          (tester) async {
        when(mockClient.userID).thenReturn('@me:example.com');
        // Viewer at 150 so they outrank Alice at 100 and canChangeRole is true.
        when(mockRoom.getPowerLevelByUserId('@me:example.com')).thenReturn(150);
        final alice = _makeUser('@alice:example.com', 'Alice', room: mockRoom);
        when(mockRoom.getPowerLevelByUserId('@alice:example.com')).thenReturn(100);
        when(mockRoom.canChangePowerLevel).thenReturn(true);
        when(mockRoom.getState(EventTypes.RoomPowerLevels)).thenReturn(null);
        when(mockRoom.requestParticipants(any)).thenAnswer((_) async => [alice]);

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Alice'));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(DropdownButton<RoomRole>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Member').last);
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();

        verifyNever(mockClient.setRoomStateWithKey(any, any, any, any));
      });

      testWidgets('custom power level shown in dropdown', (tester) async {
        final alice = _makeUser('@alice:example.com', 'Alice', room: mockRoom);
        when(mockRoom.getPowerLevelByUserId('@alice:example.com')).thenReturn(75);
        when(mockRoom.requestParticipants(any)).thenAnswer((_) async => [alice]);

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Alice'));
        await tester.pumpAndSettle();

        expect(find.text('Custom (75)'), findsWidgets);
      });

      testWidgets('role section hidden for self', (tester) async {
        when(mockClient.userID).thenReturn('@me:example.com');
        final me = _makeUser('@me:example.com', 'Me', room: mockRoom);
        when(mockRoom.requestParticipants(any)).thenAnswer((_) async => [me]);

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Me'));
        await tester.pumpAndSettle();

        expect(find.byType(DropdownButton<RoomRole>), findsNothing);
      });
    });
  });
}
