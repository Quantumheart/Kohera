import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/models/kohera_reaction.dart';
import 'package:kohera/features/chat/widgets/reaction_chips.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/openmoji_image.dart';
import 'package:mockito/annotations.dart';

@GenerateNiceMocks([MockSpec<AvatarResolver>()])
import 'reaction_chips_test.mocks.dart';

// ── Helpers ──────────────────────────────────────────────────

/// Finds a [Text.rich] whose plain text contains [text] (emoji spans render as
/// the U+FFFC placeholder, so `find.text` does not match them).
Finder _richTextContaining(String text) => find.byWidgetPredicate(
      (w) => w is Text && (w.textSpan?.toPlainText().contains(text) ?? false),
    );

/// Finds the [OpenMojiImage] rendered for [emoji].
Finder _emojiImage(String emoji) => find.byWidgetPredicate(
      (w) => w is OpenMojiImage && w.grapheme == emoji,
    );

KoheraReaction _reaction({
  required String emoji,
  int count = 1,
  bool reactedByMe = false,
  List<KoheraReactor> reactors = const [],
}) =>
    KoheraReaction(
      key: emoji,
      count: count,
      reactedByMe: reactedByMe,
      reactors: reactors,
    );

KoheraReactionList _list(List<KoheraReaction> reactions) =>
    KoheraReactionList(reactions);

Widget _wrapChips({
  required KoheraReactionList reactions,
  bool isMe = false,
  MockAvatarResolver? avatarResolver,
  void Function(String emoji)? onToggle,
}) {
  return MaterialApp(
    theme: ThemeData(splashFactory: InkRipple.splashFactory),
    home: Scaffold(
      body: ReactionChips(
        reactions: reactions,
        isMe: isMe,
        avatarResolver: avatarResolver ?? MockAvatarResolver(),
        onToggle: onToggle,
      ),
    ),
  );
}

// ── Tests ────────────────────────────────────────────────────

void main() {
  late MockAvatarResolver mockAvatarResolver;

  setUp(() {
    mockAvatarResolver = MockAvatarResolver();
  });

  testWidgets('renders nothing when no reactions', (tester) async {
    await tester.pumpWidget(
      _wrapChips(reactions: _list([])),
    );

    final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
    expect(sizedBox.width, 0);
    expect(sizedBox.height, 0);
  });

  testWidgets('renders correct chip count for multiple emojis', (tester) async {
    await tester.pumpWidget(
      _wrapChips(
        reactions: _list([
          _reaction(emoji: '\u{1F44D}'),
          _reaction(emoji: '\u{2764}\u{FE0F}'),
          _reaction(emoji: '\u{1F602}'),
        ]),
      ),
    );

    expect(_emojiImage('\u{1F44D}'), findsOneWidget);
    expect(_emojiImage('\u{2764}\u{FE0F}'), findsOneWidget);
    expect(_emojiImage('\u{1F602}'), findsOneWidget);
  });

  testWidgets('shows correct count per emoji', (tester) async {
    await tester.pumpWidget(
      _wrapChips(
        reactions: _list([
          _reaction(emoji: '\u{1F44D}', count: 3),
        ]),
      ),
    );

    expect(_emojiImage('\u{1F44D}'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('highlights chip for current user reaction', (tester) async {
    await tester.pumpWidget(
      _wrapChips(
        reactions: _list([
          _reaction(emoji: '\u{1F44D}', count: 2, reactedByMe: true),
        ]),
      ),
    );

    final cs = Theme.of(
      tester.element(find.byType(ReactionChips)),
    ).colorScheme;

    final chipContainer = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) {
          final d = c.decoration;
          return d is BoxDecoration && d.borderRadius != null;
        })
        .first;
    final decoration = chipContainer.decoration! as BoxDecoration;
    expect(decoration.color, cs.primaryContainer);
    expect(decoration.border, isNotNull);
  });

  testWidgets('no highlight for others-only reactions', (tester) async {
    await tester.pumpWidget(
      _wrapChips(
        reactions: _list([
          _reaction(emoji: '\u{1F44D}'),
        ]),
      ),
    );

    final cs = Theme.of(
      tester.element(find.byType(ReactionChips)),
    ).colorScheme;

    final chipContainer = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) {
          final d = c.decoration;
          return d is BoxDecoration && d.borderRadius != null;
        })
        .first;
    final decoration = chipContainer.decoration! as BoxDecoration;
    expect(decoration.color, cs.surfaceContainerHighest);
    final border = decoration.border! as Border;
    expect(border.top.color, isNot(cs.primary.withValues(alpha: 0.5)));
  });

  testWidgets('tap calls onToggle with correct emoji', (tester) async {
    String? tappedEmoji;
    await tester.pumpWidget(
      _wrapChips(
        reactions: _list([
          _reaction(emoji: '\u{1F44D}'),
        ]),
        onToggle: (emoji) => tappedEmoji = emoji,
      ),
    );

    await tester.tap(_emojiImage('\u{1F44D}'));
    expect(tappedEmoji, '\u{1F44D}');
  });

  testWidgets('long-press opens reactors sheet', (tester) async {
    await tester.pumpWidget(
      _wrapChips(
        reactions: _list([
          _reaction(
            emoji: '\u{1F44D}',
            reactors: [
              const KoheraReactor(
                senderId: '@alice:example.com',
                displayName: 'Alice',
              ),
            ],
          ),
        ]),
        avatarResolver: mockAvatarResolver,
      ),
    );

    await tester.longPress(_emojiImage('\u{1F44D}'));
    await tester.pumpAndSettle();

    // Bottom sheet shows the emoji (chip + sheet header) and the count.
    expect(_emojiImage('\u{1F44D}'), findsWidgets);
    expect(_richTextContaining(' 1'), findsOneWidget);
    // Should show the reactor's name
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('non-emoji reaction key falls back to text', (tester) async {
    await tester.pumpWidget(
      _wrapChips(
        reactions: _list([
          _reaction(emoji: ':custom:'),
        ]),
      ),
    );

    expect(find.text(':custom:'), findsOneWidget);
  });

  testWidgets('reactors sheet button renders OpenMoji', (tester) async {
    await tester.pumpWidget(
      _wrapChips(
        reactions: _list([
          _reaction(
            emoji: '\u{1F44D}',
            reactors: [
              const KoheraReactor(
                senderId: '@alice:example.com',
                displayName: 'Alice',
              ),
            ],
          ),
        ]),
        avatarResolver: mockAvatarResolver,
        onToggle: (_) {},
      ),
    );

    await tester.longPress(_emojiImage('\u{1F44D}'));
    await tester.pumpAndSettle();

    expect(_richTextContaining('React with '), findsOneWidget);
    // Chip + sheet header + button all render the OpenMoji image.
    expect(_emojiImage('\u{1F44D}'), findsNWidgets(3));
  });

  testWidgets('reactors sheet shows Remove your when reactedByMe',
      (tester) async {
    await tester.pumpWidget(
      _wrapChips(
        reactions: _list([
          _reaction(
            emoji: '\u{1F44D}',
            reactedByMe: true,
            reactors: [
              const KoheraReactor(
                senderId: '@me:example.com',
                displayName: 'Me',
              ),
            ],
          ),
        ]),
        avatarResolver: mockAvatarResolver,
        onToggle: (_) {},
      ),
    );

    await tester.longPress(_emojiImage('\u{1F44D}'));
    await tester.pumpAndSettle();

    expect(_richTextContaining('Remove your '), findsOneWidget);
  });
}
