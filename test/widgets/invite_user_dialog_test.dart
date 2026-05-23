import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/rooms/widgets/invite_user_dialog.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Room>(), MockSpec<Client>(), MockSpec<User>()])
import 'invite_user_dialog_test.mocks.dart';

MockRoom _makeGroupRoom(List<MockUser> participants, {int memberCount = 0}) {
  final room = MockRoom();
  when(room.isDirectChat).thenReturn(false);
  when(room.getParticipants()).thenReturn(participants);
  when(room.summary).thenReturn(RoomSummary.fromJson({
    'm.joined_member_count': memberCount,
    'm.invited_member_count': 0,
  }),);
  return room;
}

MockUser _makeUser(String id, {String? displayName}) {
  final user = MockUser();
  when(user.id).thenReturn(id);
  when(user.displayName).thenReturn(displayName);
  when(user.avatarUrl).thenReturn(null);
  return user;
}

void main() {
  late MockRoom mockRoom;

  setUp(() {
    mockRoom = MockRoom();
  });

  Widget buildTestWidget({ValueChanged<String?>? onResult}) {
    return MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                final result =
                    await InviteUserDialog.show(context, room: mockRoom);
                onResult?.call(result);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(
    WidgetTester tester, {
    ValueChanged<String?>? onResult,
  }) async {
    await tester.pumpWidget(buildTestWidget(onResult: onResult));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  group('InviteUserDialog', () {
    testWidgets('shows title and text field', (tester) async {
      await openDialog(tester);

      expect(find.text('Invite user'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Invite'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('empty input shows validation error', (tester) async {
      await openDialog(tester);

      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a Matrix ID'), findsOneWidget);
    });

    testWidgets('invalid format shows error', (tester) async {
      await openDialog(tester);

      await tester.enterText(find.byType(TextField), 'alice');
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();

      expect(
        find.text('Invalid Matrix ID (use @user:server)'),
        findsOneWidget,
      );
    });

    testWidgets('@alice without server shows error', (tester) async {
      await openDialog(tester);

      await tester.enterText(find.byType(TextField), '@alice');
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();

      expect(
        find.text('Invalid Matrix ID (use @user:server)'),
        findsOneWidget,
      );
    });

    testWidgets('alice@server (missing @) shows error', (tester) async {
      await openDialog(tester);

      await tester.enterText(find.byType(TextField), 'alice@server');
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();

      expect(
        find.text('Invalid Matrix ID (use @user:server)'),
        findsOneWidget,
      );
    });

    testWidgets('valid MXID pops dialog with value', (tester) async {
      String? result;

      // Suppress controller-disposed errors from whenComplete in show()
      final original = FlutterError.onError;
      FlutterError.onError = (d) {};
      addTearDown(() => FlutterError.onError = original);

      await openDialog(tester, onResult: (v) => result = v);

      await tester.enterText(find.byType(TextField), '@alice:matrix.org');
      await tester.tap(find.text('Invite'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(result, '@alice:matrix.org');
    });

    testWidgets('cancel closes dialog', (tester) async {
      String? result = 'sentinel';

      final original = FlutterError.onError;
      FlutterError.onError = (d) {};
      addTearDown(() => FlutterError.onError = original);

      await openDialog(tester, onResult: (v) => result = v);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(result, isNull);
    });

    testWidgets('keyboard submit triggers validation', (tester) async {
      final original = FlutterError.onError;
      FlutterError.onError = (d) {};
      addTearDown(() => FlutterError.onError = original);

      await openDialog(tester);

      await tester.enterText(find.byType(TextField), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.text('Please enter a Matrix ID'), findsOneWidget);
    });

    group('room contact suggestions', () {
      testWidgets('shows member from another room when not in current room',
          (tester) async {
        final client = MockClient();
        final alice = _makeUser('@alice:example.com', displayName: 'Alice');
        final otherRoom = _makeGroupRoom([alice], memberCount: 1);

        when(mockRoom.client).thenReturn(client);
        when(mockRoom.getParticipants()).thenReturn([]);
        when(client.userID).thenReturn('@me:example.com');
        when(client.rooms).thenReturn([otherRoom]);

        await openDialog(tester);

        expect(find.text('From other rooms'), findsOneWidget);
        expect(find.text('Alice'), findsOneWidget);
      });

      testWidgets('does not show current room members in suggestions',
          (tester) async {
        final client = MockClient();
        final alice = _makeUser('@alice:example.com', displayName: 'Alice');
        final otherRoom = _makeGroupRoom([alice], memberCount: 1);

        when(mockRoom.client).thenReturn(client);
        when(mockRoom.getParticipants()).thenReturn([alice]);
        when(client.userID).thenReturn('@me:example.com');
        when(client.rooms).thenReturn([otherRoom]);

        await openDialog(tester);

        expect(find.text('From other rooms'), findsNothing);
        expect(find.text('Alice'), findsNothing);
      });
    });
  });
}
