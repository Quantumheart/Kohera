import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/utils/openmoji.dart';
import 'package:kohera/features/chat/widgets/reaction_chips.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Event>(),
  MockSpec<Timeline>(),
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<User>(),
])
import 'reaction_chips_test.mocks.dart';

// ── Helpers ──────────────────────────────────────────────────

/// Finds a [Text.rich] whose plain text contains [text] (emoji spans render as
/// the U+FFFC placeholder, so `find.text` does not match them).
Finder _richTextContaining(String text) => find.byWidgetPredicate(
      (w) => w is Text && (w.textSpan?.toPlainText().contains(text) ?? false),
    );

/// Finds the OpenMoji [Image] rendered for [emoji].
Finder _emojiImage(String emoji) {
  final asset = openMojiAssetFor(emoji)!;
  return find.byWidgetPredicate(
    (w) =>
        w is Image &&
        w.image is AssetImage &&
        (w.image as AssetImage).assetName == asset,
  );
}

MockEvent _makeReactionEvent({
  required String senderId,
  required String emoji,
}) {
  final event = MockEvent();
  when(event.senderId).thenReturn(senderId);
  when(event.content).thenReturn({
    'm.relates_to': {'key': emoji},
  });
  return event;
}

MockEvent _makeParentEvent({
  required MockTimeline timeline,
  required List<MockEvent> reactions,
  MockRoom? room,
}) {
  final event = MockEvent();
  when(event.aggregatedEvents(timeline, RelationshipTypes.reaction))
      .thenReturn(reactions.toSet());
  when(event.hasAggregatedEvents(timeline, RelationshipTypes.reaction))
      .thenReturn(reactions.isNotEmpty);
  if (room != null) {
    when(event.room).thenReturn(room);
  }
  return event;
}

Widget _wrapChips({
  required MockEvent event,
  required MockTimeline timeline,
  required MockClient client,
  bool isMe = false,
  void Function(String emoji)? onToggle,
}) {
  return MaterialApp(
    theme: ThemeData(splashFactory: InkRipple.splashFactory),
    home: Scaffold(
      body: ReactionChips(
        event: event,
        timeline: timeline,
        client: client,
        isMe: isMe,
        onToggle: onToggle,
      ),
    ),
  );
}

// ── Tests ────────────────────────────────────────────────────

void main() {
  late MockTimeline mockTimeline;
  late MockClient mockClient;

  setUp(() {
    mockTimeline = MockTimeline();
    mockClient = MockClient();
    when(mockClient.userID).thenReturn('@me:example.com');
  });

  testWidgets('renders nothing when no reactions', (tester) async {
    final event = _makeParentEvent(
      timeline: mockTimeline,
      reactions: [],
    );

    await tester.pumpWidget(_wrapChips(
      event: event,
      timeline: mockTimeline,
      client: mockClient,
    ),);

    final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
    expect(sizedBox.width, 0);
    expect(sizedBox.height, 0);
  });

  testWidgets('renders correct chip count for multiple emojis',
      (tester) async {
    final reactions = [
      _makeReactionEvent(senderId: '@alice:example.com', emoji: '\u{1F44D}'),
      _makeReactionEvent(senderId: '@bob:example.com', emoji: '\u{2764}\u{FE0F}'),
      _makeReactionEvent(senderId: '@carol:example.com', emoji: '\u{1F602}'),
    ];

    final event = _makeParentEvent(
      timeline: mockTimeline,
      reactions: reactions,
    );

    await tester.pumpWidget(_wrapChips(
      event: event,
      timeline: mockTimeline,
      client: mockClient,
    ),);

    // Three different emojis → three OpenMoji chips (count 1, so just emoji).
    expect(_emojiImage('\u{1F44D}'), findsOneWidget);
    expect(_emojiImage('\u{2764}\u{FE0F}'), findsOneWidget);
    expect(_emojiImage('\u{1F602}'), findsOneWidget);
  });

  testWidgets('shows correct count per emoji', (tester) async {
    final reactions = [
      _makeReactionEvent(senderId: '@alice:example.com', emoji: '\u{1F44D}'),
      _makeReactionEvent(senderId: '@bob:example.com', emoji: '\u{1F44D}'),
      _makeReactionEvent(senderId: '@carol:example.com', emoji: '\u{1F44D}'),
    ];

    final event = _makeParentEvent(
      timeline: mockTimeline,
      reactions: reactions,
    );

    await tester.pumpWidget(_wrapChips(
      event: event,
      timeline: mockTimeline,
      client: mockClient,
    ),);

    // One emoji chip with count 3 (OpenMoji image + separate count Text).
    expect(_emojiImage('\u{1F44D}'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('highlights chip for current user reaction', (tester) async {
    final reactions = [
      _makeReactionEvent(senderId: '@me:example.com', emoji: '\u{1F44D}'),
      _makeReactionEvent(senderId: '@alice:example.com', emoji: '\u{1F44D}'),
    ];

    final event = _makeParentEvent(
      timeline: mockTimeline,
      reactions: reactions,
    );

    await tester.pumpWidget(_wrapChips(
      event: event,
      timeline: mockTimeline,
      client: mockClient,
    ),);

    // Find the chip container (has a BoxDecoration with borderRadius)
    final cs = Theme.of(
      tester.element(find.byType(ReactionChips)),
    ).colorScheme;

    final chipContainer = tester.widgetList<Container>(find.byType(Container))
        .where((c) {
          final d = c.decoration;
          return d is BoxDecoration && d.borderRadius != null;
        }).first;
    final decoration = chipContainer.decoration! as BoxDecoration;
    expect(decoration.color, cs.primaryContainer);
    expect(decoration.border, isNotNull);
  });

  testWidgets('no highlight for others-only reactions', (tester) async {
    final reactions = [
      _makeReactionEvent(senderId: '@alice:example.com', emoji: '\u{1F44D}'),
    ];

    final event = _makeParentEvent(
      timeline: mockTimeline,
      reactions: reactions,
    );

    await tester.pumpWidget(_wrapChips(
      event: event,
      timeline: mockTimeline,
      client: mockClient,
    ),);

    final cs = Theme.of(
      tester.element(find.byType(ReactionChips)),
    ).colorScheme;

    final chipContainer = tester.widgetList<Container>(find.byType(Container))
        .where((c) {
          final d = c.decoration;
          return d is BoxDecoration && d.borderRadius != null;
        }).first;
    final decoration = chipContainer.decoration! as BoxDecoration;
    expect(decoration.color, cs.surfaceContainerHighest);
    // Non-mine chips have an outlineVariant border (not primary).
    final border = decoration.border! as Border;
    expect(border.top.color, isNot(cs.primary.withValues(alpha: 0.5)));
  });

  testWidgets('tap calls onToggle with correct emoji', (tester) async {
    String? tappedEmoji;
    final reactions = [
      _makeReactionEvent(senderId: '@alice:example.com', emoji: '\u{1F44D}'),
    ];

    final event = _makeParentEvent(
      timeline: mockTimeline,
      reactions: reactions,
    );

    await tester.pumpWidget(_wrapChips(
      event: event,
      timeline: mockTimeline,
      client: mockClient,
      onToggle: (emoji) => tappedEmoji = emoji,
    ),);

    await tester.tap(_emojiImage('\u{1F44D}'));
    expect(tappedEmoji, '\u{1F44D}');
  });

  testWidgets('long-press opens reactors sheet', (tester) async {
    final mockRoom = MockRoom();
    final mockUser = MockUser();
    when(mockUser.displayName).thenReturn('Alice');
    when(mockUser.avatarUrl).thenReturn(null);
    when(mockRoom.unsafeGetUserFromMemoryOrFallback('@alice:example.com'))
        .thenReturn(mockUser);
    when(mockRoom.client).thenReturn(mockClient);

    final reactions = [
      _makeReactionEvent(senderId: '@alice:example.com', emoji: '\u{1F44D}'),
    ];

    final event = _makeParentEvent(
      timeline: mockTimeline,
      reactions: reactions,
      room: mockRoom,
    );

    await tester.pumpWidget(_wrapChips(
      event: event,
      timeline: mockTimeline,
      client: mockClient,
    ),);

    await tester.longPress(_emojiImage('\u{1F44D}'));
    await tester.pumpAndSettle();

    // Bottom sheet shows the emoji (chip + sheet header) and the count.
    expect(_emojiImage('\u{1F44D}'), findsWidgets);
    expect(_richTextContaining(' 1'), findsOneWidget);
    // Should show the reactor's name
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('non-emoji reaction key falls back to text', (tester) async {
    final reactions = [
      _makeReactionEvent(senderId: '@alice:example.com', emoji: ':custom:'),
    ];

    final event = _makeParentEvent(
      timeline: mockTimeline,
      reactions: reactions,
    );

    await tester.pumpWidget(_wrapChips(
      event: event,
      timeline: mockTimeline,
      client: mockClient,
    ),);

    expect(find.text(':custom:'), findsOneWidget);
  });

  testWidgets('reactors sheet button renders OpenMoji', (tester) async {
    final mockRoom = MockRoom();
    final mockUser = MockUser();
    when(mockUser.displayName).thenReturn('Alice');
    when(mockUser.avatarUrl).thenReturn(null);
    when(mockRoom.unsafeGetUserFromMemoryOrFallback('@alice:example.com'))
        .thenReturn(mockUser);
    when(mockRoom.client).thenReturn(mockClient);

    final reactions = [
      _makeReactionEvent(senderId: '@alice:example.com', emoji: '\u{1F44D}'),
    ];

    final event = _makeParentEvent(
      timeline: mockTimeline,
      reactions: reactions,
      room: mockRoom,
    );

    await tester.pumpWidget(_wrapChips(
      event: event,
      timeline: mockTimeline,
      client: mockClient,
      onToggle: (_) {},
    ),);

    await tester.longPress(_emojiImage('\u{1F44D}'));
    await tester.pumpAndSettle();

    expect(_richTextContaining('React with '), findsOneWidget);
    // Chip + sheet header + button all render the OpenMoji image.
    expect(_emojiImage('\u{1F44D}'), findsNWidgets(3));
  });
}
