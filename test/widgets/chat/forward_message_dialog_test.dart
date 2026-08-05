import 'package:flutter/material.dart';import 'package:flutter_test/flutter_test.dart';import 'package:kohera/features/chat/widgets/forward_message_dialog.dart';import 'package:kohera/shared/models/kohera_room_summary.dart';import 'package:kohera/shared/services/avatar_resolver.dart';import 'package:mockito/annotations.dart';import 'package:mockito/mockito.dart';import 'forward_message_dialog_test.mocks.dart';

@GenerateNiceMocks([MockSpec<AvatarResolver>()])

KoheraRoomSummary _room({
  required String id,
  required String name,
}) {
  return KoheraRoomSummary(
    roomId: id,
    displayname: name,
    isDirectChat: false,
    isEncrypted: true,
    isSpace: false,
    notificationCount: 0,
    highlightCount: 0,
    typingDisplayNames: const [],
    pinnedEventIds: const [],
    spaceChildCount: 0,
    isFavourite: false,
    lastEventPreview: '',
    lastEventIsThreadReply: false,
  );
}

void main() {
  late MockAvatarResolver mockAvatarResolver;

  setUp(() {
    mockAvatarResolver = MockAvatarResolver();
    when(mockAvatarResolver.resolve(any, size: anyNamed('size')))
        .thenAnswer((_) async => null);
  });

  Future<void> showDialog(
    WidgetTester tester, {
    required List<KoheraRoomSummary> targets,
    required Future<void> Function(String roomId) onForward,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => ForwardMessageDialog.show(
                  context,
                  targets: targets,
                  avatarResolver: mockAvatarResolver,
                  onForward: onForward,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  group('ForwardMessageDialog', () {
    testWidgets('shows empty message when no targets', (tester) async {
      await showDialog(tester, targets: [], onForward: (_) async {});

      expect(find.text('You have no rooms to forward to.'), findsOneWidget);
    });

    testWidgets('lists rooms sorted alphabetically', (tester) async {
      await showDialog(
        tester,
        targets: [
          _room(id: '!z:example.com', name: 'Zebra Room'),
          _room(id: '!a:example.com', name: 'Apple Room'),
          _room(id: '!m:example.com', name: 'Mango Room'),
        ],
        onForward: (_) async {},
      );

      // Rooms should be sorted alphabetically
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .where((s) => s != null && s.contains('Room'))
          .toList();
      expect(texts.length, 3);
      expect(texts[0], 'Apple Room');
      expect(texts[1], 'Mango Room');
      expect(texts[2], 'Zebra Room');
    });

    testWidgets('search filters rooms by name', (tester) async {
      await showDialog(
        tester,
        targets: [
          _room(id: '!a:example.com', name: 'Apple Room'),
          _room(id: '!b:example.com', name: 'Banana Room'),
        ],
        onForward: (_) async {},
      );

      // Type into the search field
      await tester.enterText(find.byType(TextField), 'banana');
      await tester.pumpAndSettle();

      expect(find.text('Banana Room'), findsOneWidget);
      expect(find.text('Apple Room'), findsNothing);
    });

    testWidgets('shows no matching rooms message for empty search results',
        (tester) async {
      await showDialog(
        tester,
        targets: [_room(id: '!a:example.com', name: 'Apple Room')],
        onForward: (_) async {},
      );

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();

      expect(find.text('No matching rooms.'), findsOneWidget);
    });

    testWidgets('tapping a room calls onForward and closes dialog',
        (tester) async {
      var forwardedTo = '';
      await showDialog(
        tester,
        targets: [_room(id: '!target:example.com', name: 'Target Room')],
        onForward: (roomId) async {
          forwardedTo = roomId;
        },
      );

      await tester.tap(find.text('Target Room'));
      await tester.pumpAndSettle();

      expect(forwardedTo, '!target:example.com');
      // Dialog should be closed — no more 'Forward to' title
      expect(find.text('Forward to'), findsNothing);
    });

    testWidgets('shows Forwarded snackbar on success', (tester) async {
      await showDialog(
        tester,
        targets: [_room(id: '!t:example.com', name: 'My Room')],
        onForward: (_) async {},
      );

      await tester.tap(find.text('My Room'));
      await tester.pumpAndSettle();

      expect(find.text('Forwarded to My Room'), findsOneWidget);
    });

    testWidgets('shows error snackbar when onForward throws', (tester) async {
      await showDialog(
        tester,
        targets: [_room(id: '!t:example.com', name: 'Fail Room')],
        onForward: (_) async => throw Exception('Network error'),
      );

      await tester.tap(find.text('Fail Room'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to forward'), findsOneWidget);
      // Dialog should still be open
      expect(find.text('Forward to'), findsOneWidget);
    });

    testWidgets('Cancel button closes dialog', (tester) async {
      await showDialog(
        tester,
        targets: [_room(id: '!a:example.com', name: 'Room A')],
        onForward: (_) async {},
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Forward to'), findsNothing);
    });
  });
}
