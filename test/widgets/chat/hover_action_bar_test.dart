import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/features/chat/widgets/hover_action_bar.dart';
import 'package:kohera/shared/widgets/openmoji_image.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Finds the [OpenMojiImage] rendered for [emoji].
Finder _emojiImage(String emoji) => find.byWidgetPredicate(
      (w) => w is OpenMojiImage && w.grapheme == emoji,
    );

void main() {
  Widget buildTestWidget({
    VoidCallback? onReact,
    void Function(String emoji)? onQuickReact,
    VoidCallback? onReply,
    void Function(Offset position)? onMore,
    PreferencesService? prefs,
  }) {
    return ChangeNotifierProvider<PreferencesService>(
      create: (_) => prefs ?? PreferencesService(),
      child: MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Scaffold(
          body: Center(
            child: HoverActionBar(
              cs: const ColorScheme.light(),
              onReact: onReact,
              onQuickReact: onQuickReact,
              onReply: onReply,
              onMore: onMore ?? (_) {},
            ),
          ),
        ),
      ),
    );
  }

  group('HoverActionBar', () {
    testWidgets('shows more icon always', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    });

    testWidgets('shows react icon when onQuickReact provided', (tester) async {
      await tester.pumpWidget(buildTestWidget(onQuickReact: (_) {}));
      expect(find.byIcon(Icons.add_reaction_outlined), findsOneWidget);
    });

    testWidgets('hides react icon when no react callbacks', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byIcon(Icons.add_reaction_outlined), findsNothing);
    });

    testWidgets('shows reply icon when onReply provided', (tester) async {
      await tester.pumpWidget(buildTestWidget(onReply: () {}));
      expect(find.byIcon(Icons.reply_rounded), findsOneWidget);
    });

    testWidgets('action buttons use a clickable pointer cursor',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        onQuickReact: (_) {},
        onReply: () {},
      ),);

      for (final icon in [
        Icons.add_reaction_outlined,
        Icons.reply_rounded,
        Icons.more_horiz_rounded,
      ]) {
        final inkWell = tester.widget<InkWell>(
          find.ancestor(
            of: find.byIcon(icon),
            matching: find.byType(InkWell),
          ),
        );
        expect(inkWell.mouseCursor, SystemMouseCursors.click);
      }
    });

    testWidgets('hides reply icon when onReply is null', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byIcon(Icons.reply_rounded), findsNothing);
    });

    testWidgets('tap reply calls onReply', (tester) async {
      var called = false;
      await tester.pumpWidget(buildTestWidget(onReply: () => called = true));

      await tester.tap(find.byIcon(Icons.reply_rounded));
      expect(called, isTrue);
    });

    testWidgets('tap more calls onMore', (tester) async {
      Offset? pos;
      await tester.pumpWidget(buildTestWidget(onMore: (p) => pos = p));

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      expect(pos, isNotNull);
    });

    testWidgets('tap react icon opens quick-react overlay with emojis',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(onQuickReact: (_) {}));

      await tester.tap(find.byIcon(Icons.add_reaction_outlined));
      await tester.pumpAndSettle();

      expect(_emojiImage('\u{2764}\u{FE0F}'), findsOneWidget);
      expect(_emojiImage('\u{1F44D}'), findsOneWidget);
      expect(_emojiImage('\u{1F44E}'), findsOneWidget);
      expect(_emojiImage('\u{1F602}'), findsOneWidget);
      expect(_emojiImage('\u{1F622}'), findsOneWidget);
      expect(_emojiImage('\u{1F62E}'), findsOneWidget);
    });

    testWidgets('tap emoji in overlay calls onQuickReact and closes overlay',
        (tester) async {
      String? selectedEmoji;
      await tester.pumpWidget(
        buildTestWidget(onQuickReact: (e) => selectedEmoji = e),
      );

      await tester.tap(find.byIcon(Icons.add_reaction_outlined));
      await tester.pumpAndSettle();

      await tester.tap(_emojiImage('\u{1F44D}'));
      await tester.pumpAndSettle();

      expect(selectedEmoji, '\u{1F44D}');
      expect(_emojiImage('\u{1F602}'), findsNothing);
    });

    Widget buildEdgeWidget(Alignment alignment) =>
        ChangeNotifierProvider<PreferencesService>(
          create: (_) => PreferencesService(),
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: alignment,
                child: HoverActionBar(
                  cs: const ColorScheme.light(),
                  onQuickReact: (_) {},
                  onMore: (_) {},
                ),
              ),
            ),
          ),
        );

    testWidgets('quick-react bar stays on-screen near the left edge',
        (tester) async {
      await tester.pumpWidget(buildEdgeWidget(Alignment.centerLeft));
      await tester.tap(find.byIcon(Icons.add_reaction_outlined));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(_emojiImage('\u{2764}\u{FE0F}')).dx,
        greaterThanOrEqualTo(0),
      );
    });

    testWidgets('quick-react bar stays on-screen near the right edge',
        (tester) async {
      await tester.pumpWidget(buildEdgeWidget(Alignment.centerRight));
      await tester.tap(find.byIcon(Icons.add_reaction_outlined));
      await tester.pumpAndSettle();

      final screenWidth = tester.getSize(find.byType(Scaffold)).width;
      expect(
        tester.getTopRight(_emojiImage('\u{1F62E}')).dx,
        lessThanOrEqualTo(screenWidth),
      );
    });

    testWidgets('quick-react applies the default skin tone', (tester) async {
      SharedPreferences.setMockInitialValues({'emoji_skin_tone': 'dark'});
      final sp = await SharedPreferences.getInstance();
      final prefs = PreferencesService(prefs: sp);
      String? reacted;

      await tester.pumpWidget(
        buildTestWidget(prefs: prefs, onQuickReact: (e) => reacted = e),
      );
      await tester.tap(find.byIcon(Icons.add_reaction_outlined));
      await tester.pumpAndSettle();

      // 👍 is toned; ❤️ (no variant) stays base.
      expect(_emojiImage('\u{1F44D}\u{1F3FF}'), findsOneWidget);
      expect(_emojiImage('\u{2764}\u{FE0F}'), findsOneWidget);

      await tester.tap(_emojiImage('\u{1F44D}\u{1F3FF}'));
      expect(reacted, '\u{1F44D}\u{1F3FF}');
    });
  });
}
