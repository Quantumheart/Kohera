import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
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
      expect(find.text('Member'), findsOneWidget);
    });

    testWidgets('kick action prompts for reason and forwards it to client.kick',
        (tester) async {
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
  });
}
