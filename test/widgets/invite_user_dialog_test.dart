import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/rooms/widgets/invite_user_dialog.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Client>(), MockSpec<Room>()])
import 'invite_user_dialog_test.mocks.dart';

void main() {
  late MockRoom mockRoom;
  late MockClient mockClient;

  setUp(() {
    mockRoom = MockRoom();
    mockClient = MockClient();
    when(mockRoom.client).thenReturn(mockClient);
    when(mockRoom.getParticipants()).thenReturn([]);
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.searchUserDirectory(any, limit: anyNamed('limit')))
        .thenAnswer((_) async => SearchUserDirectoryResponse(
              results: [],
              limited: false,
            ),);
  });

  Widget buildTestWidget({ValueChanged<String?>? onResult}) {
    return MaterialApp(
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

  Future<void> submitField(WidgetTester tester) async {
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  group('InviteUserDialog', () {
    testWidgets('shows title and text field', (tester) async {
      await openDialog(tester);

      expect(find.text('Invite user'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('empty input on submit shows validation error',
        (tester) async {
      await openDialog(tester);

      await submitField(tester);

      expect(find.text('Please enter a Matrix ID'), findsOneWidget);
    });

    testWidgets('invalid format shows error', (tester) async {
      await openDialog(tester);

      await tester.enterText(find.byType(TextField), 'alice');
      await submitField(tester);

      expect(
        find.text('Invalid Matrix ID (use @user:server)'),
        findsOneWidget,
      );
    });

    testWidgets('@alice without server shows error', (tester) async {
      await openDialog(tester);

      await tester.enterText(find.byType(TextField), '@alice');
      await submitField(tester);

      expect(
        find.text('Invalid Matrix ID (use @user:server)'),
        findsOneWidget,
      );
    });

    testWidgets('alice@server (missing @) shows error', (tester) async {
      await openDialog(tester);

      await tester.enterText(find.byType(TextField), 'alice@server');
      await submitField(tester);

      expect(
        find.text('Invalid Matrix ID (use @user:server)'),
        findsOneWidget,
      );
    });

    testWidgets('valid MXID pops dialog with value on submit', (tester) async {
      String? result;

      await openDialog(tester, onResult: (v) => result = v);

      await tester.enterText(find.byType(TextField), '@alice:matrix.org');
      await submitField(tester);

      expect(result, '@alice:matrix.org');
    });

    testWidgets('barrier dismiss returns null', (tester) async {
      String? result = 'sentinel';

      await openDialog(tester, onResult: (v) => result = v);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('shows recent contacts from existing DMs', (tester) async {
      final dmRoom = MockRoom();
      when(dmRoom.isDirectChat).thenReturn(true);
      when(dmRoom.directChatMatrixID).thenReturn('@bob:example.com');
      when(dmRoom.getLocalizedDisplayname()).thenReturn('Bob');
      when(dmRoom.avatar).thenReturn(null);
      when(mockClient.rooms).thenReturn([dmRoom]);

      await openDialog(tester);

      expect(find.text('Recent contacts'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('hides existing room members from recent contacts',
        (tester) async {
      final dmRoom = MockRoom();
      when(dmRoom.isDirectChat).thenReturn(true);
      when(dmRoom.directChatMatrixID).thenReturn('@bob:example.com');
      when(dmRoom.getLocalizedDisplayname()).thenReturn('Bob');
      when(dmRoom.avatar).thenReturn(null);
      when(mockClient.rooms).thenReturn([dmRoom]);

      // Bob is already in the room we're inviting to.
      final bob = User('@bob:example.com', room: mockRoom);
      when(mockRoom.getParticipants()).thenReturn([bob]);

      await openDialog(tester);

      expect(find.text('Recent contacts'), findsNothing);
      expect(find.text('Bob'), findsNothing);
    });

    testWidgets('tapping a suggestion pops with that MXID', (tester) async {
      String? result;

      final dmRoom = MockRoom();
      when(dmRoom.isDirectChat).thenReturn(true);
      when(dmRoom.directChatMatrixID).thenReturn('@bob:example.com');
      when(dmRoom.getLocalizedDisplayname()).thenReturn('Bob');
      when(dmRoom.avatar).thenReturn(null);
      when(mockClient.rooms).thenReturn([dmRoom]);

      await openDialog(tester, onResult: (v) => result = v);

      await tester.tap(find.text('Bob'));
      await tester.pumpAndSettle();

      expect(result, '@bob:example.com');
    });

    testWidgets('searches user directory after typing', (tester) async {
      when(mockClient.searchUserDirectory(any, limit: anyNamed('limit')))
          .thenAnswer((_) async => SearchUserDirectoryResponse(
                results: [
                  Profile(
                    userId: '@carol:example.com',
                    displayName: 'Carol',
                  ),
                ],
                limited: false,
              ),);

      await openDialog(tester);

      await tester.enterText(find.byType(TextField), 'car');
      // debounce is 300ms
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      verify(mockClient.searchUserDirectory('car', limit: 20)).called(1);
      expect(find.text('Carol'), findsOneWidget);
      expect(find.text('@carol:example.com'), findsOneWidget);
    });

    testWidgets('shows empty-state hint when search returns no results',
        (tester) async {
      await openDialog(tester);

      await tester.enterText(find.byType(TextField), 'nobody');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(
        find.text('No matching users. Press Enter to invite by Matrix ID.'),
        findsOneWidget,
      );
    });
  });
}
