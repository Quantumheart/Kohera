import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/services/sticker_pack_service.dart';
import 'package:matrix/matrix.dart';

/// A suggestion entry for the custom emoji autocomplete overlay.
class EmojiSuggestion {
  final String shortcode;
  final Uri url;

  const EmojiSuggestion({required this.shortcode, required this.url});
}

/// Encapsulates autocomplete state and logic for `:shortcode:` custom emoji.
///
/// Listens to a [TextEditingController], detects the `:` trigger character,
/// filters custom emoji from the room's MSC2545 packs by shortcode, and
/// inserts the selected `:shortcode:` text.
class EmojiAutocompleteController extends ChangeNotifier {
  EmojiAutocompleteController({
    required this.textController,
    required this.room,
    required this.stickerPacks,
    this.debounceDuration = const Duration(milliseconds: 150),
  }) {
    textController.addListener(_onTextChanged);
  }

  final TextEditingController textController;
  final Room room;
  final StickerPackService stickerPacks;
  @visibleForTesting
  final Duration debounceDuration;

  static final _queryRegex = RegExp(r'^[\w-]*$');

  /// Minimum query length before activating, to reduce noise (e.g. `http://`).
  static const _minQueryLength = 2;

  Timer? _debounce;
  bool _isActive = false;
  int _triggerOffset = -1;
  String _query = '';
  List<EmojiSuggestion> _suggestions = [];
  int _selectedIndex = 0;

  bool get isActive => _isActive;
  String get query => _query;
  List<EmojiSuggestion> get suggestions => _suggestions;
  int get selectedIndex => _selectedIndex;

  /// Whether the overlay has visible suggestions that can be confirmed.
  bool get hasSuggestions => _isActive && _suggestions.isNotEmpty;

  // ── Trigger detection ──────────────────────────────────────

  void _onTextChanged() {
    final text = textController.text;
    final selection = textController.selection;

    if (!selection.isValid || !selection.isCollapsed) {
      _dismiss();
      return;
    }

    final cursorPos = selection.baseOffset;
    if (cursorPos < 0 || cursorPos > text.length) {
      _dismiss();
      return;
    }

    // Walk backwards from cursor to find the last `:`.
    final textBeforeCursor = text.substring(0, cursorPos);
    final triggerPos = textBeforeCursor.lastIndexOf(':');

    if (triggerPos < 0) {
      _dismiss();
      return;
    }

    // Trigger must be at start of text or preceded by whitespace.
    if (triggerPos > 0 &&
        text[triggerPos - 1] != ' ' &&
        text[triggerPos - 1] != '\n') {
      _dismiss();
      return;
    }

    // Query must contain only shortcode characters (no spaces/colons).
    final queryText = text.substring(triggerPos + 1, cursorPos);
    if (!_queryRegex.hasMatch(queryText)) {
      _dismiss();
      return;
    }

    // Require a minimum length to reduce noise from stray colons.
    if (queryText.length < _minQueryLength) {
      _dismiss();
      return;
    }

    _triggerOffset = triggerPos;
    _query = queryText;
    _isActive = true;
    _selectedIndex = 0;

    _debounce?.cancel();
    if (debounceDuration == Duration.zero) {
      _updateSuggestions();
    } else {
      _debounce = Timer(debounceDuration, _updateSuggestions);
    }
  }

  // ── Filtering ──────────────────────────────────────────────

  void _updateSuggestions() {
    final lowerQuery = _query.toLowerCase();
    final seen = <String>{};
    final results = <EmojiSuggestion>[];

    for (final pack in stickerPacks.packsForRoom(room)) {
      for (final image in pack.emoji) {
        if (!seen.add(image.shortcode)) continue;
        if (!image.shortcode.toLowerCase().contains(lowerQuery)) continue;
        results.add(
          EmojiSuggestion(shortcode: image.shortcode, url: image.url),
        );
        if (results.length >= 30) break;
      }
      if (results.length >= 30) break;
    }

    _suggestions = results;
    notifyListeners();
  }

  // ── Keyboard navigation ────────────────────────────────────

  void moveUp() {
    if (_suggestions.isEmpty) return;
    _selectedIndex = (_selectedIndex - 1).clamp(0, _suggestions.length - 1);
    notifyListeners();
  }

  void moveDown() {
    if (_suggestions.isEmpty) return;
    _selectedIndex = (_selectedIndex + 1).clamp(0, _suggestions.length - 1);
    notifyListeners();
  }

  // ── Selection ──────────────────────────────────────────────

  /// Confirm the currently selected suggestion.
  void confirmSelection() {
    if (_suggestions.isEmpty) return;
    selectSuggestion(_suggestions[_selectedIndex]);
  }

  /// Insert `:shortcode:` for [suggestion], replacing the trigger + query.
  void selectSuggestion(EmojiSuggestion suggestion) {
    final text = textController.text;
    final emojiText = ':${suggestion.shortcode}: ';

    final before = text.substring(0, _triggerOffset);
    final cursorPos = textController.selection.baseOffset;
    final after = text.substring(cursorPos);

    final newText = '$before$emojiText$after';
    final newCursor = before.length + emojiText.length;

    textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );

    _dismiss();
  }

  // ── Dismissal ──────────────────────────────────────────────

  void dismiss() => _dismiss();

  void _dismiss() {
    _debounce?.cancel();
    if (!_isActive) return;
    _isActive = false;
    _triggerOffset = -1;
    _query = '';
    _suggestions = [];
    _selectedIndex = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    textController.removeListener(_onTextChanged);
    super.dispose();
  }
}
