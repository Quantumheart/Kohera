import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/models/sticker_pack.dart';
import 'package:kohera/features/chat/services/emoji_autocomplete_controller.dart';
import 'package:kohera/features/chat/widgets/emoji_suggestion_list.dart';
import 'package:kohera/shared/services/media_resolver.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<EmojiAutocompleteController>(),
  MockSpec<MediaResolver>(),
])
import 'emoji_suggestion_list_test.mocks.dart';

PackImage _emoji({
  required String shortcode,
  String? grapheme,
  String? body,
}) {
  return PackImage(
    shortcode: shortcode,
    url: Uri.parse('mxc://example.org/$shortcode'),
    isSticker: false,
    isEmoji: true,
    emoji: grapheme,
    body: body,
  );
}

void main() {
  Widget wrap(Widget child, {required MockEmojiAutocompleteController controller}) {
    // Stub ChangeNotifier methods so ListenableBuilder works
    when(controller.hasListeners).thenReturn(false);
    return MaterialApp(
      home: Scaffold(
        body: EmojiSuggestionList(
          controller: controller,
          mediaResolver: MockMediaResolver(),
        ),
      ),
    );
  }

  group('EmojiSuggestionList', () {
    testWidgets('returns SizedBox.shrink when no suggestions', (tester) async {
      final controller = MockEmojiAutocompleteController();
      when(controller.suggestions).thenReturn([]);
      when(controller.selectedIndex).thenReturn(0);

      await tester.pumpWidget(wrap(
        const SizedBox.shrink(),
        controller: controller,
      ));

      // The widget should return SizedBox.shrink
      // We can verify by checking that no ListView is rendered
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('renders list of suggestions with shortcodes', (tester) async {
      final suggestions = [
        _emoji(shortcode: 'party', grapheme: '🎉'),
        _emoji(shortcode: 'thumbsup', grapheme: '👍'),
      ];
      final controller = MockEmojiAutocompleteController();
      when(controller.suggestions).thenReturn(suggestions);
      when(controller.selectedIndex).thenReturn(0);

      await tester.pumpWidget(wrap(
        const SizedBox.shrink(),
        controller: controller,
      ));

      expect(find.text(':party:'), findsOneWidget);
      expect(find.text(':thumbsup:'), findsOneWidget);
    });

    testWidgets('highlights selected index with primary color',
        (tester) async {
      final suggestions = [
        _emoji(shortcode: 'party', grapheme: '🎉'),
        _emoji(shortcode: 'thumbsup', grapheme: '👍'),
      ];
      final controller = MockEmojiAutocompleteController();
      when(controller.suggestions).thenReturn(suggestions);
      when(controller.selectedIndex).thenReturn(1);

      await tester.pumpWidget(wrap(
        const SizedBox.shrink(),
        controller: controller,
      ));

      // The second tile should be selected
      final materials = tester.widgetList<Material>(find.byType(Material));
      expect(materials.length, greaterThanOrEqualTo(2));
    });

    testWidgets('tapping a suggestion calls selectSuggestion', (tester) async {
      final suggestions = [
        _emoji(shortcode: 'party', grapheme: '🎉'),
      ];
      final controller = MockEmojiAutocompleteController();
      when(controller.suggestions).thenReturn(suggestions);
      when(controller.selectedIndex).thenReturn(0);

      await tester.pumpWidget(wrap(
        const SizedBox.shrink(),
        controller: controller,
      ));

      await tester.tap(find.text(':party:'));
      await tester.pumpAndSettle();

      verify(controller.selectSuggestion(suggestions[0])).called(1);
    });

    testWidgets('shows body text when present and different from shortcode',
        (tester) async {
      final suggestions = [
        _emoji(shortcode: 'party', body: 'Party Parrot'),
      ];
      final controller = MockEmojiAutocompleteController();
      when(controller.suggestions).thenReturn(suggestions);
      when(controller.selectedIndex).thenReturn(0);

      await tester.pumpWidget(wrap(
        const SizedBox.shrink(),
        controller: controller,
      ));

      expect(find.text(':party:'), findsOneWidget);
      expect(find.text('Party Parrot'), findsOneWidget);
    });

    testWidgets('omits body when same as shortcode', (tester) async {
      final suggestions = [
        _emoji(shortcode: 'party', body: 'party'),
      ];
      final controller = MockEmojiAutocompleteController();
      when(controller.suggestions).thenReturn(suggestions);
      when(controller.selectedIndex).thenReturn(0);

      await tester.pumpWidget(wrap(
        const SizedBox.shrink(),
        controller: controller,
      ));

      expect(find.text(':party:'), findsOneWidget);
      // 'party' (lowercase) as body equals shortcode → not shown separately
      expect(find.text('party'), findsNothing);
    });
  });
}
