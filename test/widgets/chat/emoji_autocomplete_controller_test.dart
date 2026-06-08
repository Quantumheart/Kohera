import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/models/sticker_pack.dart';
import 'package:kohera/core/services/sticker_pack_service.dart';
import 'package:kohera/features/chat/widgets/emoji_autocomplete_controller.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<StickerPackService>(),
  MockSpec<Room>(),
])
import 'emoji_autocomplete_controller_test.mocks.dart';

// ── Helpers ──────────────────────────────────────────────────

PackImage _makeEmoji(String shortcode, {String? body}) => PackImage(
      shortcode: shortcode,
      url: Uri.parse('mxc://example.com/$shortcode'),
      isSticker: false,
      isEmoji: true,
      body: body,
    );

StickerPack _makePack(List<PackImage> emoji, {String id = 'test-pack'}) =>
    StickerPack(
      id: id,
      displayName: 'Test Pack',
      stickers: const [],
      emoji: emoji,
    );

EmojiAutocompleteController _makeCtrl({
  required TextEditingController textCtrl,
  required MockStickerPackService service,
  required MockRoom room,
}) =>
    EmojiAutocompleteController(
      textController: textCtrl,
      stickerPackService: service,
      room: room,
      debounceDuration: Duration.zero,
    );

void main() {
  group('EmojiAutocompleteController', () {
    late TextEditingController textCtrl;
    late MockStickerPackService mockService;
    late MockRoom mockRoom;

    final waveEmoji = _makeEmoji('wave', body: 'Waving hand');
    final thumbsUpEmoji = _makeEmoji('thumbsup', body: 'Thumbs up');
    final heartEmoji = _makeEmoji('heart', body: 'Heart');
    final testPack = _makePack([waveEmoji, thumbsUpEmoji, heartEmoji]);

    setUp(() {
      textCtrl = TextEditingController();
      mockService = MockStickerPackService();
      mockRoom = MockRoom();
      when(mockService.packsForRoom(any)).thenReturn([testPack]);
    });

    tearDown(() {
      textCtrl.dispose();
    });

    // ── Trigger detection ──────────────────────────────────────

    test('no text → not active', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      expect(ctrl.isActive, isFalse);

      ctrl.dispose();
    });

    test('plain text without colon → not active', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: 'hello world',
        selection: TextSelection.collapsed(offset: 11),
      );

      expect(ctrl.isActive, isFalse);

      ctrl.dispose();
    });

    test(': at position 0 → active with empty query', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':',
        selection: TextSelection.collapsed(offset: 1),
      );

      expect(ctrl.isActive, isTrue);
      expect(ctrl.query, '');

      ctrl.dispose();
    });

    test(':abc → active with query "abc"', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':wav',
        selection: TextSelection.collapsed(offset: 4),
      );

      expect(ctrl.isActive, isTrue);
      expect(ctrl.query, 'wav');

      ctrl.dispose();
    });

    test(': after space → active', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: 'hello :wav',
        selection: TextSelection.collapsed(offset: 10),
      );

      expect(ctrl.isActive, isTrue);
      expect(ctrl.query, 'wav');

      ctrl.dispose();
    });

    test(': after newline → active', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: 'hello\n:wav',
        selection: TextSelection.collapsed(offset: 10),
      );

      expect(ctrl.isActive, isTrue);

      ctrl.dispose();
    });

    test(': after non-whitespace → not active', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: 'word:wav',
        selection: TextSelection.collapsed(offset: 8),
      );

      expect(ctrl.isActive, isFalse);

      ctrl.dispose();
    });

    test('space in query → dismissed', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':wave hand',
        selection: TextSelection.collapsed(offset: 10),
      );

      expect(ctrl.isActive, isFalse);

      ctrl.dispose();
    });

    test('closed shortcode :wave: → not active', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':wave:',
        selection: TextSelection.collapsed(offset: 6),
      );

      expect(ctrl.isActive, isFalse);

      ctrl.dispose();
    });

    test('non-collapsed selection → not active', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':wav',
        selection: TextSelection(baseOffset: 1, extentOffset: 4),
      );

      expect(ctrl.isActive, isFalse);

      ctrl.dispose();
    });

    // ── Filtering ──────────────────────────────────────────────

    test('empty query → returns all emoji from pack', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':',
        selection: TextSelection.collapsed(offset: 1),
      );

      expect(ctrl.suggestions.length, 3);

      ctrl.dispose();
    });

    test('query matches shortcode → filtered results', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':wav',
        selection: TextSelection.collapsed(offset: 4),
      );

      expect(ctrl.suggestions.length, 1);
      expect(ctrl.suggestions[0].shortcode, 'wave');

      ctrl.dispose();
    });

    test('query matches body → filtered results', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':waving',
        selection: TextSelection.collapsed(offset: 7),
      );

      expect(ctrl.suggestions.length, 1);
      expect(ctrl.suggestions[0].shortcode, 'wave');

      ctrl.dispose();
    });

    test('matching is case-insensitive', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':WAV',
        selection: TextSelection.collapsed(offset: 4),
      );

      expect(ctrl.suggestions.length, 1);
      expect(ctrl.suggestions[0].shortcode, 'wave');

      ctrl.dispose();
    });

    test('no match → empty suggestions', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':zzzznotanemoji',
        selection: TextSelection.collapsed(offset: 15),
      );

      expect(ctrl.suggestions, isEmpty);

      ctrl.dispose();
    });

    test('results capped at 20 even with many emoji', () {
      final manyEmoji =
          List.generate(30, (i) => _makeEmoji('emoji_$i'));
      when(mockService.packsForRoom(any))
          .thenReturn([_makePack(manyEmoji)]);

      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':',
        selection: TextSelection.collapsed(offset: 1),
      );

      expect(ctrl.suggestions.length, 20);

      ctrl.dispose();
    });

    test('emoji from multiple packs are combined', () {
      final packA = _makePack([waveEmoji], id: 'pack-a');
      final packB = _makePack([thumbsUpEmoji, heartEmoji], id: 'pack-b');
      when(mockService.packsForRoom(any)).thenReturn([packA, packB]);

      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':',
        selection: TextSelection.collapsed(offset: 1),
      );

      expect(ctrl.suggestions.length, 3);

      ctrl.dispose();
    });

    // ── Selection ──────────────────────────────────────────────

    test('selectSuggestion inserts :shortcode: and dismisses', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':wav',
        selection: TextSelection.collapsed(offset: 4),
      );

      expect(ctrl.suggestions.isNotEmpty, isTrue);
      ctrl.selectSuggestion(ctrl.suggestions[0]);

      expect(textCtrl.text, ':wave: ');
      expect(textCtrl.selection.baseOffset, 7);
      expect(ctrl.isActive, isFalse);

      ctrl.dispose();
    });

    test('selectSuggestion inserts the grapheme for built-in OpenMoji', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':grin',
        selection: TextSelection.collapsed(offset: 5),
      );

      final openMoji = PackImage(
        shortcode: 'grinning_face',
        url: Uri.parse('openmoji://1F600'),
        isSticker: false,
        isEmoji: true,
        body: 'grinning face',
        emoji: '😀',
      );
      ctrl.selectSuggestion(openMoji);

      expect(textCtrl.text, '😀 ');
      expect(ctrl.isActive, isFalse);

      ctrl.dispose();
    });

    test('selectSuggestion preserves text before trigger', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: 'hello :wav',
        selection: TextSelection.collapsed(offset: 10),
      );

      ctrl.selectSuggestion(ctrl.suggestions[0]);

      expect(textCtrl.text, 'hello :wave: ');

      ctrl.dispose();
    });

    test('selectSuggestion preserves text after cursor', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':wav thanks',
        selection: TextSelection.collapsed(offset: 4),
      );

      ctrl.selectSuggestion(ctrl.suggestions[0]);

      expect(textCtrl.text, ':wave:  thanks');

      ctrl.dispose();
    });

    test('confirmSelection selects item at selectedIndex', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':',
        selection: TextSelection.collapsed(offset: 1),
      );

      ctrl.moveDown(); // index → 1 (thumbsup)
      ctrl.confirmSelection();

      expect(textCtrl.text, ':thumbsup: ');

      ctrl.dispose();
    });

    test('confirmSelection does nothing when suggestions empty', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':zzzznotanemoji',
        selection: TextSelection.collapsed(offset: 15),
      );

      expect(ctrl.suggestions, isEmpty);
      ctrl.confirmSelection(); // Should not throw.
      expect(textCtrl.text, ':zzzznotanemoji');

      ctrl.dispose();
    });

    // ── Keyboard navigation ────────────────────────────────────

    test('moveDown increments selectedIndex', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':',
        selection: TextSelection.collapsed(offset: 1),
      );

      expect(ctrl.selectedIndex, 0);
      ctrl.moveDown();
      expect(ctrl.selectedIndex, 1);
      ctrl.moveDown();
      expect(ctrl.selectedIndex, 2);

      ctrl.dispose();
    });

    test('moveDown clamps at last suggestion', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':',
        selection: TextSelection.collapsed(offset: 1),
      );

      for (var i = 0; i < 10; i++) {
        ctrl.moveDown();
      }
      expect(ctrl.selectedIndex, 2); // 3 emoji, max index 2.

      ctrl.dispose();
    });

    test('moveUp decrements selectedIndex', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':',
        selection: TextSelection.collapsed(offset: 1),
      );

      ctrl.moveDown();
      ctrl.moveDown();
      expect(ctrl.selectedIndex, 2);

      ctrl.moveUp();
      expect(ctrl.selectedIndex, 1);

      ctrl.dispose();
    });

    test('moveUp clamps at 0', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':',
        selection: TextSelection.collapsed(offset: 1),
      );

      ctrl.moveUp();
      expect(ctrl.selectedIndex, 0);

      ctrl.dispose();
    });

    test('moveDown does nothing when suggestions empty', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':zzzzz',
        selection: TextSelection.collapsed(offset: 6),
      );

      expect(ctrl.suggestions, isEmpty);
      ctrl.moveDown(); // Should not throw.
      expect(ctrl.selectedIndex, 0);

      ctrl.dispose();
    });

    test('selectedIndex resets when query changes', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':',
        selection: TextSelection.collapsed(offset: 1),
      );

      ctrl.moveDown();
      expect(ctrl.selectedIndex, 1);

      textCtrl.value = const TextEditingValue(
        text: ':w',
        selection: TextSelection.collapsed(offset: 2),
      );
      expect(ctrl.selectedIndex, 0);

      ctrl.dispose();
    });

    // ── Dismissal ──────────────────────────────────────────────

    test('dismiss() clears all state', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':wav',
        selection: TextSelection.collapsed(offset: 4),
      );

      expect(ctrl.isActive, isTrue);
      ctrl.dismiss();

      expect(ctrl.isActive, isFalse);
      expect(ctrl.suggestions, isEmpty);
      expect(ctrl.query, '');
      expect(ctrl.selectedIndex, 0);

      ctrl.dispose();
    });

    // ── hasSuggestions ─────────────────────────────────────────

    test('hasSuggestions is true only when active with results', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      expect(ctrl.hasSuggestions, isFalse);

      textCtrl.value = const TextEditingValue(
        text: ':wav',
        selection: TextSelection.collapsed(offset: 4),
      );
      expect(ctrl.hasSuggestions, isTrue);

      textCtrl.value = const TextEditingValue(
        text: ':zzzzz',
        selection: TextSelection.collapsed(offset: 6),
      );
      expect(ctrl.isActive, isTrue);
      expect(ctrl.hasSuggestions, isFalse);

      ctrl.dispose();
    });

    // ── Lifecycle ──────────────────────────────────────────────

    test('text changes after dispose do not throw', () {
      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      ctrl.dispose();

      // Should not throw after dispose.
      textCtrl.value = const TextEditingValue(
        text: ':wav',
        selection: TextSelection.collapsed(offset: 4),
      );
    });

    test('no packs → empty suggestions but still active', () {
      when(mockService.packsForRoom(any)).thenReturn([]);

      final ctrl = _makeCtrl(
          textCtrl: textCtrl, service: mockService, room: mockRoom,);

      textCtrl.value = const TextEditingValue(
        text: ':wav',
        selection: TextSelection.collapsed(offset: 4),
      );

      expect(ctrl.isActive, isTrue);
      expect(ctrl.suggestions, isEmpty);
      expect(ctrl.hasSuggestions, isFalse);

      ctrl.dispose();
    });
  });
}
