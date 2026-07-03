import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/rooms/models/kohera_room_summary.dart';
import 'package:kohera/features/rooms/widgets/add_existing_rooms_dialog.dart';

KoheraRoomSummary makeRoom(String id, String name, {bool isSpace = false}) =>
    KoheraRoomSummary(
      roomId: id,
      displayname: name,
      isDirectChat: false,
      isEncrypted: false,
      isSpace: isSpace,
      notificationCount: 0,
      highlightCount: 0,
      typingDisplayNames: const [],
      pinnedEventIds: const [],
      spaceChildCount: 0,
      isFavourite: false,
      lastEventPreview: '',
      lastEventIsThreadReply: false,
    );

void main() {
  Widget buildTestWidget({
    required List<KoheraRoomSummary> candidateRooms,
    required Future<int> Function(List<String> roomIds) onAddRooms,
    Set<String> existingChildIds = const {},
  }) {
    return MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => AddExistingRoomsDialog.show(
                context,
                candidateRooms: candidateRooms,
                existingChildIds: existingChildIds,
                avatarResolver: null,
                onAddRooms: onAddRooms,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(
    WidgetTester tester, {
    required List<KoheraRoomSummary> candidateRooms,
    required Future<int> Function(List<String> roomIds) onAddRooms,
    Set<String> existingChildIds = const {},
  }) async {
    await tester.pumpWidget(
      buildTestWidget(
        candidateRooms: candidateRooms,
        existingChildIds: existingChildIds,
        onAddRooms: onAddRooms,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<int> noopAdd(List<String> ids) async => 0;

  group('AddExistingRoomsDialog', () {
    testWidgets('shows empty state when all rooms in space', (tester) async {
      await openDialog(tester, candidateRooms: const [], onAddRooms: noopAdd);

      expect(
        find.text('All your rooms are already in this space.'),
        findsOneWidget,
      );
    });

    testWidgets('shows eligible rooms', (tester) async {
      await openDialog(
        tester,
        candidateRooms: [makeRoom('!r1:x', 'Alpha'), makeRoom('!r2:x', 'Beta')],
        onAddRooms: noopAdd,
      );

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('excludes rooms already in space', (tester) async {
      await openDialog(
        tester,
        candidateRooms: [makeRoom('!r1:x', 'Alpha'), makeRoom('!r2:x', 'Beta')],
        existingChildIds: const {'!r1:x'},
        onAddRooms: noopAdd,
      );

      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('excludes space rooms', (tester) async {
      await openDialog(
        tester,
        candidateRooms: [makeRoom('!r1:x', 'Alpha', isSpace: true)],
        onAddRooms: noopAdd,
      );

      expect(
        find.text('All your rooms are already in this space.'),
        findsOneWidget,
      );
    });

    testWidgets('search filters by display name', (tester) async {
      await openDialog(
        tester,
        candidateRooms: [makeRoom('!r1:x', 'Alpha'), makeRoom('!r2:x', 'Beta')],
        onAddRooms: noopAdd,
      );

      await tester.enterText(find.byType(TextField), 'alp');
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);
    });

    testWidgets('selection updates Add button text', (tester) async {
      await openDialog(
        tester,
        candidateRooms: [makeRoom('!r1:x', 'Alpha'), makeRoom('!r2:x', 'Beta')],
        onAddRooms: noopAdd,
      );

      expect(find.text('Add (0)'), findsOneWidget);

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      expect(find.text('Add (1)'), findsOneWidget);

      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      expect(find.text('Add (2)'), findsOneWidget);
    });

    testWidgets('submit calls onAddRooms with selected room ids',
        (tester) async {
      List<String>? submitted;
      await openDialog(
        tester,
        candidateRooms: [makeRoom('!r1:x', 'Alpha'), makeRoom('!r2:x', 'Beta')],
        onAddRooms: (ids) async {
          submitted = ids;
          return 0;
        },
      );

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add (2)'));
      await tester.pumpAndSettle();

      expect(submitted, ['!r1:x', '!r2:x']);
    });

    testWidgets('partial failure shows SnackBar', (tester) async {
      await openDialog(
        tester,
        candidateRooms: [makeRoom('!r1:x', 'Alpha'), makeRoom('!r2:x', 'Beta')],
        onAddRooms: (ids) async => 1,
      );

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Failed to add 1 room(s)'), findsOneWidget);
    });
  });
}
