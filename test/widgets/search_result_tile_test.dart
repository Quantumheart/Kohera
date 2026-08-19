import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/models/kohera_message_display.dart';
import 'package:kohera/data/models/kohera_message_status.dart';
import 'package:kohera/data/services/avatar_resolver.dart';
import 'package:kohera/features/chat/models/room_search_result.dart';
import 'package:kohera/features/chat/widgets/search_result_tile.dart';
import 'package:kohera/shared/widgets/pixel_sprite_avatar.dart';

/// A no-op [AvatarResolver] for tests — always returns null so the
/// fallback initial is shown.
class _NullAvatarResolver implements AvatarResolver {
  const _NullAvatarResolver();
  @override
  Future<AvatarThumbnail?> resolve(String? mxcUrl,
      {required double size}) async => null;
}

/// Extracts the full text from a [TextSpan] tree.
String spanText(InlineSpan span) {
  if (span is TextSpan) {
    return (span.text ?? '') +
        (span.children?.map(spanText).join() ?? '');
  }
  return '';
}

/// Returns the full text content of every [RichText] in the tree.
List<String> richTexts(WidgetTester tester) {
  return tester
      .widgetList<RichText>(find.byType(RichText))
      .map((r) => spanText(r.text))
      .toList();
}

/// Finds [RichText] widgets whose concatenated text contains [needle].
Finder richTextContaining(String needle) => find.byWidgetPredicate(
      (w) => w is RichText && spanText(w.text).contains(needle),
    );

void main() {
  const avatarResolver = _NullAvatarResolver();

  KoheraMessageDisplay makeMessage({
    String eventId = r'$evt1',
    String senderId = '@alice:example.com',
    String senderName = 'Alice',
    String body = 'Hello world',
    DateTime? timestamp,
  }) {
    return KoheraMessageDisplay(
      eventId: eventId,
      senderId: senderId,
      senderName: senderName,
      body: body,
      messageType: 'm.text',
      eventType: 'm.room.message',
      timestamp: timestamp ?? DateTime(2024, 1, 1, 12),
      status: KoheraMessageStatus.sent,
      content: const {},
    );
  }

  Widget buildTestWidget({required Widget child}) {
    return MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(body: child),
    );
  }

  group('SearchResultTile', () {
    testWidgets('renders main hit sender and body', (tester) async {
      final result = RoomSearchResult(message: makeMessage());

      await tester.pumpWidget(
        buildTestWidget(
          child: SearchResultTile(
            result: result,
            avatarResolver: avatarResolver,
            query: 'hello',
            onTap: () {},
          ),
        ),
      );

      expect(find.text('Alice'), findsOneWidget);
      expect(richTextContaining('Hello world'), findsOneWidget);
    });

    testWidgets('highlighted match has bold weight', (tester) async {
      final result =
          RoomSearchResult(message: makeMessage(body: 'Say hello to you'));

      await tester.pumpWidget(
        buildTestWidget(
          child: SearchResultTile(
            result: result,
            avatarResolver: avatarResolver,
            query: 'hello',
            onTap: () {},
          ),
        ),
      );

      // The highlighted RichText is the last one (the main body).
      final richText = tester.widget<RichText>(find.byType(RichText).last);
      final textSpan = richText.text as TextSpan;
      final matchSpan = textSpan.children!
          .cast<TextSpan>()
          .firstWhere((s) => s.text?.toLowerCase() == 'hello');
      expect(matchSpan.style?.fontWeight, FontWeight.w600);
    });

    testWidgets('renders context before the hit', (tester) async {
      final result = RoomSearchResult(
        message: makeMessage(body: 'hello match'),
        contextBefore: [
          makeMessage(eventId: r'$b1', senderName: 'Bob', body: 'before one'),
          makeMessage(eventId: r'$b2', senderName: 'Carol', body: 'before two'),
        ],
      );

      await tester.pumpWidget(
        buildTestWidget(
          child: SearchResultTile(
            result: result,
            avatarResolver: avatarResolver,
            query: 'hello',
            onTap: () {},
          ),
        ),
      );

      expect(richTextContaining('Bob: before one'), findsOneWidget);
      expect(richTextContaining('Carol: before two'), findsOneWidget);
    });

    testWidgets('renders context after the hit', (tester) async {
      final result = RoomSearchResult(
        message: makeMessage(body: 'hello match'),
        contextAfter: [
          makeMessage(eventId: r'$a1', senderName: 'Dan', body: 'after one'),
          makeMessage(eventId: r'$a2', senderName: 'Eve', body: 'after two'),
        ],
      );

      await tester.pumpWidget(
        buildTestWidget(
          child: SearchResultTile(
            result: result,
            avatarResolver: avatarResolver,
            query: 'hello',
            onTap: () {},
          ),
        ),
      );

      expect(richTextContaining('Dan: after one'), findsOneWidget);
      expect(richTextContaining('Eve: after two'), findsOneWidget);
    });

    testWidgets('caps context at 3 before and 3 after', (tester) async {
      final result = RoomSearchResult(
        message: makeMessage(body: 'hello match'),
        contextBefore: [
          for (var i = 0; i < 5; i++)
            makeMessage(eventId: r'$b$i', senderName: 'B$i', body: 'before $i'),
        ],
        contextAfter: [
          for (var i = 0; i < 5; i++)
            makeMessage(eventId: r'$a$i', senderName: 'A$i', body: 'after $i'),
        ],
      );

      await tester.pumpWidget(
        buildTestWidget(
          child: SearchResultTile(
            result: result,
            avatarResolver: avatarResolver,
            query: 'hello',
            onTap: () {},
          ),
        ),
      );

      // Only first 3 before and first 3 after should render.
      expect(richTextContaining('B0: before 0'), findsOneWidget);
      expect(richTextContaining('B1: before 1'), findsOneWidget);
      expect(richTextContaining('B2: before 2'), findsOneWidget);
      expect(richTextContaining('B3:'), findsNothing);
      expect(richTextContaining('B4:'), findsNothing);

      expect(richTextContaining('A0: after 0'), findsOneWidget);
      expect(richTextContaining('A1: after 1'), findsOneWidget);
      expect(richTextContaining('A2: after 2'), findsOneWidget);
      expect(richTextContaining('A3:'), findsNothing);
      expect(richTextContaining('A4:'), findsNothing);
    });

    testWidgets('context lines are dimmed at 0.4 opacity', (tester) async {
      final result = RoomSearchResult(
        message: makeMessage(body: 'hello match'),
        contextBefore: [
          makeMessage(eventId: r'$b1', senderName: 'Bob', body: 'dimmed ctx'),
        ],
      );

      await tester.pumpWidget(
        buildTestWidget(
          child: SearchResultTile(
            result: result,
            avatarResolver: avatarResolver,
            query: 'hello',
            onTap: () {},
          ),
        ),
      );

      // Find the Opacity widget wrapping the context line.
      final opacityFinder = find.ancestor(
        of: richTextContaining('Bob: dimmed ctx'),
        matching: find.byType(Opacity),
      );
      expect(opacityFinder, findsOneWidget);
      final opacity = tester.widget<Opacity>(opacityFinder);
      expect(opacity.opacity, 0.4);
    });

    testWidgets('context lines have a left border indent', (tester) async {
      final result = RoomSearchResult(
        message: makeMessage(body: 'hello match'),
        contextBefore: [
          makeMessage(eventId: r'$b1', senderName: 'Bob', body: 'bordered ctx'),
        ],
      );

      await tester.pumpWidget(
        buildTestWidget(
          child: SearchResultTile(
            result: result,
            avatarResolver: avatarResolver,
            query: 'hello',
            onTap: () {},
          ),
        ),
      );

      // The context line container should have a BoxDecoration with a left
      // border.
      final containerFinder = find.ancestor(
        of: richTextContaining('Bob: bordered ctx'),
        matching: find.byType(Container),
      );
      expect(containerFinder, findsWidgets);

      final container = tester.widget<Container>(containerFinder.first);
      final decoration = container.decoration! as BoxDecoration;
      final border = decoration.border! as Border;
      expect(border.left.width, 2);
    });

    testWidgets('main hit shows avatar', (tester) async {
      final result = RoomSearchResult(message: makeMessage());

      await tester.pumpWidget(
        buildTestWidget(
          child: SearchResultTile(
            result: result,
            avatarResolver: avatarResolver,
            query: 'hello',
            onTap: () {},
          ),
        ),
      );

      // The main hit renders a UserAvatar which falls back to PixelSpriteAvatar.
      expect(find.byType(PixelSpriteAvatar), findsOneWidget);
    });

    testWidgets('context lines do not render avatars', (tester) async {
      final result = RoomSearchResult(
        message: makeMessage(body: 'hello match'),
        contextBefore: [
          makeMessage(eventId: r'$b1', senderName: 'Bob', body: 'no avatar ctx'),
        ],
        contextAfter: [
          makeMessage(eventId: r'$a1', senderName: 'Dan', body: 'no avatar ctx'),
        ],
      );

      await tester.pumpWidget(
        buildTestWidget(
          child: SearchResultTile(
            result: result,
            avatarResolver: avatarResolver,
            query: 'hello',
            onTap: () {},
          ),
        ),
      );

      // Only one avatar (the main hit) — context lines have none.
      expect(find.byType(PixelSpriteAvatar), findsOneWidget);
    });

    testWidgets('tap fires callback', (tester) async {
      var tapped = false;
      final result = RoomSearchResult(message: makeMessage());

      await tester.pumpWidget(
        buildTestWidget(
          child: SearchResultTile(
            result: result,
            avatarResolver: avatarResolver,
            query: 'hello',
            onTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.text('Alice'));
      expect(tapped, isTrue);
    });

    testWidgets('renders with no context (empty before/after)',
        (tester) async {
      final result = RoomSearchResult(message: makeMessage(body: 'solo hit'));

      await tester.pumpWidget(
        buildTestWidget(
          child: SearchResultTile(
            result: result,
            avatarResolver: avatarResolver,
            query: 'solo',
            onTap: () {},
          ),
        ),
      );

      expect(find.text('Alice'), findsOneWidget);
      // No context lines — only the main hit body RichText and the sender
      // name Text (which internally renders a RichText).
      expect(richTextContaining('solo hit'), findsOneWidget);
      // No context-style "Name: body" lines should be present.
      expect(richTextContaining(': '), findsNothing);
    });

    testWidgets('context body is single-line ellipsized', (tester) async {
      const longBody = 'This is a very long context message body '
          'that should be ellipsized to a single line because context lines '
          'are constrained to maxLines one with ellipsis overflow.';
      final result = RoomSearchResult(
        message: makeMessage(body: 'hello match'),
        contextBefore: [
          makeMessage(eventId: r'$b1', senderName: 'Bob', body: longBody),
        ],
      );

      await tester.pumpWidget(
        buildTestWidget(
          child: SearchResultTile(
            result: result,
            avatarResolver: avatarResolver,
            query: 'hello',
            onTap: () {},
          ),
        ),
      );

      // The context RichText should have maxLines = 1.
      final ctxRichText = tester.widget<RichText>(
        richTextContaining('Bob:'),
      );
      expect(ctxRichText.maxLines, 1);
      expect(ctxRichText.overflow, TextOverflow.ellipsis);
    });

    testWidgets('shows (edited) indicator for edited messages', (tester) async {
      final result = RoomSearchResult(
        message: makeMessage(body: 'edited body').copyWith(isEdited: true),
      );

      await tester.pumpWidget(
        buildTestWidget(
          child: SearchResultTile(
            result: result,
            avatarResolver: avatarResolver,
            query: 'edited',
            onTap: () {},
          ),
        ),
      );

      expect(find.text('(edited)'), findsOneWidget);
    });

    testWidgets('does not show (edited) for non-edited messages',
        (tester) async {
      final result = RoomSearchResult(message: makeMessage());

      await tester.pumpWidget(
        buildTestWidget(
          child: SearchResultTile(
            result: result,
            avatarResolver: avatarResolver,
            query: 'hello',
            onTap: () {},
          ),
        ),
      );

      expect(find.text('(edited)'), findsNothing);
    });

    testWidgets('shows thread icon for thread root messages', (tester) async {
      final result = RoomSearchResult(
        message: makeMessage().copyWith(threadRootId: r'$threadRoot'),
      );

      await tester.pumpWidget(
        buildTestWidget(
          child: SearchResultTile(
            result: result,
            avatarResolver: avatarResolver,
            query: 'hello',
            onTap: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.forum_rounded), findsOneWidget);
    });

    testWidgets('does not show thread icon for non-thread messages',
        (tester) async {
      final result = RoomSearchResult(message: makeMessage());

      await tester.pumpWidget(
        buildTestWidget(
          child: SearchResultTile(
            result: result,
            avatarResolver: avatarResolver,
            query: 'hello',
            onTap: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.forum_rounded), findsNothing);
    });
  });
}
