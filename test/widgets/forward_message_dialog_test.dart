import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/widgets/forward_message_dialog.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
])
import 'forward_message_dialog_test.mocks.dart';

void main() {
  late MockClient mockClient;

  MockRoom buildRoom(String name) {
    final room = MockRoom();
    when(room.id).thenReturn('!${name.toLowerCase()}:example.com');
    when(room.membership).thenReturn(Membership.join);
    when(room.isSpace).thenReturn(false);
    when(room.avatar).thenReturn(null);
    when(room.client).thenReturn(mockClient);
    when(room.getLocalizedDisplayname()).thenReturn(name);
    return room;
  }

  setUp(() {
    mockClient = MockClient();
    when(mockClient.rooms).thenReturn([]);
  });

  Widget buildTestWidget() {
    return MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                unawaited(
                  ForwardMessageDialog.show(context, client: mockClient),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  group('ForwardMessageDialog', () {
    testWidgets('shows search field and title', (tester) async {
      await openDialog(tester);

      expect(find.text('Forward to'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Search rooms'), findsOneWidget);
    });

    testWidgets('lists joined non-space rooms', (tester) async {
      when(mockClient.rooms).thenReturn([
        buildRoom('Alpha'),
        buildRoom('Bravo'),
      ]);

      await openDialog(tester);

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsOneWidget);
    });

    testWidgets('excludes spaces and non-joined rooms', (tester) async {
      final space = buildRoom('SpaceRoom');
      when(space.isSpace).thenReturn(true);
      final invited = buildRoom('InvitedRoom');
      when(invited.membership).thenReturn(Membership.invite);
      when(mockClient.rooms).thenReturn([
        buildRoom('Alpha'),
        space,
        invited,
      ]);

      await openDialog(tester);

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('SpaceRoom'), findsNothing);
      expect(find.text('InvitedRoom'), findsNothing);
    });

    testWidgets('filters rooms by search text', (tester) async {
      when(mockClient.rooms).thenReturn([
        buildRoom('Alpha'),
        buildRoom('Bravo'),
      ]);

      await openDialog(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Search rooms'),
        'brav',
      );
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Bravo'), findsOneWidget);
    });

    testWidgets('returns selected room on tap', (tester) async {
      final alpha = buildRoom('Alpha');
      when(mockClient.rooms).thenReturn([alpha]);

      Room? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    picked = await ForwardMessageDialog.show(
                      context,
                      client: mockClient,
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();

      expect(picked, same(alpha));
    });

    testWidgets('shows empty state when no rooms', (tester) async {
      await openDialog(tester);

      expect(find.text('No rooms available.'), findsOneWidget);
    });

    testWidgets('cancel button closes dialog', (tester) async {
      await openDialog(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Forward to'), findsNothing);
    });
  });
}
