import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/rooms/models/kohera_room_summary.dart';
import 'package:kohera/features/rooms/widgets/add_room_to_space_dialog.dart';

KoheraRoomSummary makeSpace(String id, String name) => KoheraRoomSummary(
      roomId: id,
      displayname: name,
      isDirectChat: false,
      isEncrypted: false,
      isSpace: true,
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
    required List<KoheraRoomSummary> candidateSpaces,
    required Future<int> Function(Map<String, bool> selections) onAddToSpaces,
    Set<String> memberSpaceIds = const {},
  }) {
    return MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => AddRoomToSpaceDialog.show(
                context,
                roomId: '!room:example.com',
                candidateSpaces: candidateSpaces,
                memberSpaceIds: memberSpaceIds,
                avatarResolver: null,
                onAddToSpaces: onAddToSpaces,
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
    required List<KoheraRoomSummary> candidateSpaces,
    required Future<int> Function(Map<String, bool> selections) onAddToSpaces,
    Set<String> memberSpaceIds = const {},
    bool hasListView = false,
  }) async {
    await tester.pumpWidget(
      buildTestWidget(
        candidateSpaces: candidateSpaces,
        onAddToSpaces: onAddToSpaces,
        memberSpaceIds: memberSpaceIds,
      ),
    );
    await tester.tap(find.text('Open'));
    if (hasListView) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    } else {
      await tester.pumpAndSettle();
    }
  }

  Future<int> noopAdd(Map<String, bool> selections) async => 0;

  group('AddRoomToSpaceDialog', () {
    testWidgets('shows empty state when room in all spaces', (tester) async {
      await openDialog(
        tester,
        candidateSpaces: const [],
        onAddToSpaces: noopAdd,
      );

      expect(
        find.text('This room is already in all your spaces.'),
        findsOneWidget,
      );
    });

    testWidgets('shows eligible spaces', (tester) async {
      await openDialog(
        tester,
        candidateSpaces: [makeSpace('!s1:x', 'Space A'), makeSpace('!s2:x', 'Space B')],
        onAddToSpaces: noopAdd,
        hasListView: true,
      );

      expect(find.text('Space A'), findsOneWidget);
      expect(find.text('Space B'), findsOneWidget);
    });

    testWidgets('excludes spaces where room is already a member',
        (tester) async {
      await openDialog(
        tester,
        candidateSpaces: [makeSpace('!s1:x', 'Space A'), makeSpace('!s2:x', 'Space B')],
        memberSpaceIds: const {'!s1:x'},
        onAddToSpaces: noopAdd,
        hasListView: true,
      );

      expect(find.text('Space A'), findsNothing);
      expect(find.text('Space B'), findsOneWidget);
    });

    testWidgets('shows empty state when no eligible spaces', (tester) async {
      await openDialog(
        tester,
        candidateSpaces: const [],
        onAddToSpaces: noopAdd,
      );

      expect(
        find.text('This room is already in all your spaces.'),
        findsOneWidget,
      );
    });

    testWidgets('selection enables Add button', (tester) async {
      await openDialog(
        tester,
        candidateSpaces: [makeSpace('!s1:x', 'Space A')],
        onAddToSpaces: noopAdd,
        hasListView: true,
      );

      final addButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Add'),
      );
      expect(addButton.onPressed, isNull);

      await tester.tap(find.text('Space A'));
      await tester.pump();

      final addButton2 = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Add'),
      );
      expect(addButton2.onPressed, isNotNull);
    });

    testWidgets('suggested switch enabled only when space selected',
        (tester) async {
      await openDialog(
        tester,
        candidateSpaces: [makeSpace('!s1:x', 'Space A')],
        onAddToSpaces: noopAdd,
        hasListView: true,
      );

      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.onChanged, isNull);

      await tester.tap(find.text('Space A'));
      await tester.pump();

      final switchWidget2 = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget2.onChanged, isNotNull);
    });

    testWidgets('submit calls onAddToSpaces with suggested flag',
        (tester) async {
      Map<String, bool>? submitted;
      await openDialog(
        tester,
        candidateSpaces: [makeSpace('!s1:x', 'Space A')],
        onAddToSpaces: (selections) async {
          submitted = selections;
          return 0;
        },
        hasListView: true,
      );

      await tester.tap(find.text('Space A'));
      await tester.pump();

      await tester.tap(find.byType(Switch));
      await tester.pump();

      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(submitted, {'!s1:x': true});
    });

    testWidgets('partial failure shows SnackBar', (tester) async {
      await openDialog(
        tester,
        candidateSpaces: [makeSpace('!s1:x', 'Space A')],
        onAddToSpaces: (selections) async => 1,
        hasListView: true,
      );

      await tester.tap(find.text('Space A'));
      await tester.pump();

      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Failed to add room to 1 space(s)'), findsOneWidget);
    });

    testWidgets('cancel closes without side effects', (tester) async {
      var called = false;
      await openDialog(
        tester,
        candidateSpaces: [makeSpace('!s1:x', 'Space A')],
        onAddToSpaces: (selections) async {
          called = true;
          return 0;
        },
        hasListView: true,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Add to space'), findsNothing);
      expect(called, isFalse);
    });
  });
}
