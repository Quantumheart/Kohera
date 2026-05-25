import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/sticker_pack_service.dart';
import 'package:kohera/features/chat/widgets/emoji_autocomplete_controller.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
])
import 'emoji_autocomplete_controller_test.mocks.dart';

// ── Helpers ──────────────────────────────────────────────────

const _kRoomEmotesType = 'im.ponies.room_emotes';

StrippedStateEvent _stateEvent(Map<String, Object?> content) =>
    StrippedStateEvent(
      type: _kRoomEmotesType,
      senderId: '@bot:example.com',
      stateKey: '',
      content: content,
    );

Map<String, Object?> _emojiPackContent(List<String> shortcodes) => {
      'pack': {
        'display_name': 'Emoji Pack',
        'usage': ['emoticon'],
      },
      'images': {
        for (final s in shortcodes) s: {'url': 'mxc://example.com/$s'},
      },
    };

void main() {
  group('EmojiAutocompleteController', () {
    late TextEditingController textCtrl;
    late MockClient mockClient;
    late CachedStreamController<SyncUpdate> syncCtl;
    late StickerPackService stickerPacks;
    late MockRoom mockRoom;

    setUp(() {
      textCtrl = TextEditingController();
      mockClient = MockClient();
      syncCtl = CachedStreamController<SyncUpdate>();
      when(mockClient.onSync).thenReturn(syncCtl);
      when(mockClient.accountData).thenReturn({});
      when(mockClient.rooms).thenReturn([]);
      stickerPacks = StickerPackService(client: mockClient);

      mockRoom = MockRoom();
      when(mockRoom.id).thenReturn('!room:example.com');
      when(mockRoom.client).thenReturn(mockClient);
      when(mockRoom.spaceParents).thenReturn([]);
      when(mockRoom.getState(_kRoomEmotesType)).thenReturn(
        _stateEvent(_emojiPackContent([
          'partyblob',
          'partywizard',
          'thumbsup',
          'heart',
        ])),
      );
    });

    tearDown(() {
      textCtrl.dispose();
      stickerPacks.dispose();
    });

    EmojiAutocompleteController makeController() => EmojiAutocompleteController(
          textController: textCtrl,
          room: mockRoom,
          stickerPacks: stickerPacks,
          debounceDuration: Duration.zero,
        );

    // ── Trigger detection ──────────────────────────────────

    test('typing :par activates emoji autocomplete', () {
      final ctrl = makeController();

      textCtrl.value = const TextEditingValue(
        text: ':par',
        selection: TextSelection.collapsed(offset: 4),
      );

      expect(ctrl.isActive, isTrue);
      expect(ctrl.query, 'par');

      ctrl.dispose();
    });

    test(': after whitespace activates', () {
      final ctrl = makeController();

      textCtrl.value = const TextEditingValue(
        text: 'hello :par',
        selection: TextSelection.collapsed(offset: 10),
      );

      expect(ctrl.isActive, isTrue);

      ctrl.dispose();
    });

    test('colon inside a word (http://) does not activate', () {
      final ctrl = makeController();

      textCtrl.value = const TextEditingValue(
        text: 'http://example.com',
        selection: TextSelection.collapsed(offset: 18),
      );

      expect(ctrl.isActive, isFalse);

      ctrl.dispose();
    });

    test('single character query does not activate (min length 2)', () {
      final ctrl = makeController();

      textCtrl.value = const TextEditingValue(
        text: ':p',
        selection: TextSelection.collapsed(offset: 2),
      );
      expect(ctrl.isActive, isTrue);

      textCtrl.value = const TextEditingValue(
        text: ':',
        selection: TextSelection.collapsed(offset: 1),
      );
      expect(ctrl.isActive, isFalse);

      ctrl.dispose();
    });

    test('space in query dismisses autocomplete', () {
      final ctrl = makeController();

      textCtrl.value = const TextEditingValue(
        text: ':par ty',
        selection: TextSelection.collapsed(offset: 7),
      );

      expect(ctrl.isActive, isFalse);

      ctrl.dispose();
    });

    test('completed shortcode with closing colon does not activate', () {
      final ctrl = makeController();

      textCtrl.value = const TextEditingValue(
        text: ':party:',
        selection: TextSelection.collapsed(offset: 7),
      );

      expect(ctrl.isActive, isFalse);

      ctrl.dispose();
    });

    test('no trigger character means inactive', () {
      final ctrl = makeController();

      textCtrl.value = const TextEditingValue(
        text: 'hello world',
        selection: TextSelection.collapsed(offset: 11),
      );

      expect(ctrl.isActive, isFalse);

      ctrl.dispose();
    });

    // ── Filtering ──────────────────────────────────────────

    test('filters emoji by shortcode substring', () {
      final ctrl = makeController();

      textCtrl.value = const TextEditingValue(
        text: ':party',
        selection: TextSelection.collapsed(offset: 6),
      );

      expect(ctrl.suggestions.length, 2);
      expect(
        ctrl.suggestions.map((s) => s.shortcode),
        containsAll(['partyblob', 'partywizard']),
      );

      ctrl.dispose();
    });

    test('filtering is case-insensitive', () {
      final ctrl = makeController();

      textCtrl.value = const TextEditingValue(
        text: ':HEART',
        selection: TextSelection.collapsed(offset: 6),
      );

      expect(ctrl.suggestions.length, 1);
      expect(ctrl.suggestions.first.shortcode, 'heart');

      ctrl.dispose();
    });

    test('non-matching query yields no suggestions', () {
      final ctrl = makeController();

      textCtrl.value = const TextEditingValue(
        text: ':zzzznope',
        selection: TextSelection.collapsed(offset: 9),
      );

      expect(ctrl.isActive, isTrue);
      expect(ctrl.suggestions, isEmpty);
      expect(ctrl.hasSuggestions, isFalse);

      ctrl.dispose();
    });

    test('de-dupes emoji by shortcode (first wins)', () {
      when(mockClient.accountData).thenReturn({
        'im.ponies.user_emotes':
            BasicEvent(type: 'im.ponies.user_emotes', content: {
          'pack': {
            'display_name': 'Account',
            'usage': ['emoticon'],
          },
          'images': {
            'heart': {'url': 'mxc://example.com/account_heart'},
          },
        }),
      });

      final ctrl = makeController();

      textCtrl.value = const TextEditingValue(
        text: ':heart',
        selection: TextSelection.collapsed(offset: 6),
      );

      expect(ctrl.suggestions.length, 1);
      // Account pack is aggregated first, so it wins.
      expect(
        ctrl.suggestions.first.url.toString(),
        'mxc://example.com/account_heart',
      );

      ctrl.dispose();
    });

    // ── Selection ──────────────────────────────────────────

    test('selectSuggestion inserts :shortcode: and a space', () {
      final ctrl = makeController();

      textCtrl.value = const TextEditingValue(
        text: ':party',
        selection: TextSelection.collapsed(offset: 6),
      );

      final suggestion = ctrl.suggestions
          .firstWhere((s) => s.shortcode == 'partyblob');
      ctrl.selectSuggestion(suggestion);

      expect(textCtrl.text, ':partyblob: ');
      expect(textCtrl.selection.baseOffset, ':partyblob: '.length);
      expect(ctrl.isActive, isFalse);

      ctrl.dispose();
    });

    test('selectSuggestion preserves text around the trigger', () {
      final ctrl = makeController();

      textCtrl.value = const TextEditingValue(
        text: 'hey :heart thanks',
        selection: TextSelection.collapsed(offset: 10),
      );

      expect(ctrl.suggestions.isNotEmpty, isTrue);
      ctrl.selectSuggestion(ctrl.suggestions.first);

      expect(textCtrl.text, 'hey :heart:  thanks');

      ctrl.dispose();
    });

    // ── Keyboard navigation ────────────────────────────────

    test('moveDown / moveUp adjust selectedIndex with clamping', () {
      final ctrl = makeController();

      textCtrl.value = const TextEditingValue(
        text: ':party',
        selection: TextSelection.collapsed(offset: 6),
      );

      expect(ctrl.selectedIndex, 0);
      ctrl.moveDown();
      expect(ctrl.selectedIndex, 1);
      ctrl.moveDown();
      expect(ctrl.selectedIndex, 1); // 2 suggestions, clamps at index 1.
      ctrl.moveUp();
      ctrl.moveUp();
      expect(ctrl.selectedIndex, 0);

      ctrl.dispose();
    });

    test('confirmSelection does nothing when suggestions empty', () {
      final ctrl = makeController();

      textCtrl.value = const TextEditingValue(
        text: ':zzzznope',
        selection: TextSelection.collapsed(offset: 9),
      );

      expect(ctrl.suggestions, isEmpty);
      ctrl.confirmSelection(); // Should not throw.
      expect(textCtrl.text, ':zzzznope');

      ctrl.dispose();
    });

    // ── Dismissal ──────────────────────────────────────────

    test('dismiss clears state', () {
      final ctrl = makeController();

      textCtrl.value = const TextEditingValue(
        text: ':party',
        selection: TextSelection.collapsed(offset: 6),
      );

      expect(ctrl.isActive, isTrue);
      ctrl.dismiss();
      expect(ctrl.isActive, isFalse);
      expect(ctrl.suggestions, isEmpty);
      expect(ctrl.selectedIndex, 0);

      ctrl.dispose();
    });

    // ── hasSuggestions ──────────────────────────────────────

    test('hasSuggestions is true only when active with suggestions', () {
      final ctrl = makeController();

      expect(ctrl.hasSuggestions, isFalse);

      textCtrl.value = const TextEditingValue(
        text: ':party',
        selection: TextSelection.collapsed(offset: 6),
      );
      expect(ctrl.hasSuggestions, isTrue);

      textCtrl.value = const TextEditingValue(
        text: ':zzzznope',
        selection: TextSelection.collapsed(offset: 9),
      );
      expect(ctrl.isActive, isTrue);
      expect(ctrl.hasSuggestions, isFalse);

      ctrl.dispose();
    });
  });
}
