import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/rooms/widgets/invite_user_dialog.dart';
import 'package:kohera/shared/models/kohera_user_summary.dart';

InviteUserDialogParams _params({
  Set<String> existingMemberIds = const {},
  List<KoheraUserSummary> knownContacts = const [],
  List<KoheraUserSummary> roomContacts = const [],
  Future<List<KoheraUserSummary>> Function(String query)? onSearchUserDirectory,
}) =>
    InviteUserDialogParams(
      roomId: '!room:example.com',
      existingMemberIds: existingMemberIds,
      knownContacts: knownContacts,
      roomContacts: roomContacts,
      onSearchUserDirectory: onSearchUserDirectory ?? (_) async => const [],
    );

KoheraUserSummary _user(String id, {String? displayName}) => KoheraUserSummary(
      userId: id,
      displayname: displayName ?? id,
    );

void main() {
  Widget buildTestWidget(
    InviteUserDialogParams params, {
    ValueChanged<String?>? onResult,
  }) {
    return MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                final result =
                    await InviteUserDialog.show(context, params: params);
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
    WidgetTester tester,
    InviteUserDialogParams params, {
    ValueChanged<String?>? onResult,
  }) async {
    await tester.pumpWidget(buildTestWidget(params, onResult: onResult));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  group('InviteUserDialog', () {
    testWidgets('shows title and text field', (tester) async {
      await openDialog(tester, _params());

      expect(find.text('Invite user'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Invite'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('empty input shows validation error', (tester) async {
      await openDialog(tester, _params());

      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a Matrix ID'), findsOneWidget);
    });

    testWidgets('invalid format shows error', (tester) async {
      await openDialog(tester, _params());

      await tester.enterText(find.byType(TextField), 'alice');
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();

      expect(
        find.text('Invalid Matrix ID (use @user:server)'),
        findsOneWidget,
      );
    });

    testWidgets('@alice without server shows error', (tester) async {
      await openDialog(tester, _params());

      await tester.enterText(find.byType(TextField), '@alice');
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();

      expect(
        find.text('Invalid Matrix ID (use @user:server)'),
        findsOneWidget,
      );
    });

    testWidgets('alice@server (missing @) shows error', (tester) async {
      await openDialog(tester, _params());

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

      final original = FlutterError.onError;
      FlutterError.onError = (d) {};
      addTearDown(() => FlutterError.onError = original);

      await openDialog(tester, _params(), onResult: (v) => result = v);

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

      await openDialog(tester, _params(), onResult: (v) => result = v);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(result, isNull);
    });

    testWidgets('keyboard submit triggers validation', (tester) async {
      final original = FlutterError.onError;
      FlutterError.onError = (d) {};
      addTearDown(() => FlutterError.onError = original);

      await openDialog(tester, _params());

      await tester.enterText(find.byType(TextField), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.text('Please enter a Matrix ID'), findsOneWidget);
    });

    group('room contact suggestions', () {
      testWidgets('shows member from another room when not in current room',
          (tester) async {
        await openDialog(
          tester,
          _params(
            roomContacts: [_user('@alice:example.com', displayName: 'Alice')],
          ),
        );

        expect(find.text('From other rooms'), findsOneWidget);
        expect(find.text('Alice'), findsOneWidget);
      });

      testWidgets('does not show current room members in suggestions',
          (tester) async {
        await openDialog(
          tester,
          _params(
            existingMemberIds: {'@alice:example.com'},
            roomContacts: [_user('@alice:example.com', displayName: 'Alice')],
          ),
        );

        expect(find.text('From other rooms'), findsNothing);
        expect(find.text('Alice'), findsNothing);
      });

      testWidgets('search invokes onSearchUserDirectory and shows results',
          (tester) async {
        await openDialog(
          tester,
          _params(
            onSearchUserDirectory: (q) async =>
                [_user('@bob:example.com', displayName: 'Bob')],
          ),
        );

        await tester.enterText(find.byType(TextField), 'bob');
        // Debounce is 400ms.
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(find.text('Bob'), findsOneWidget);
      });
    });
  });
}
