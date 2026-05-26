import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/models/sticker_pack.dart';
import 'package:kohera/core/services/sticker_pack_service.dart';
import 'package:matrix/matrix.dart';

/// Encapsulates autocomplete state and logic for custom emoji triggered by `:`.
///
/// Listens to a [TextEditingController], detects the `:` trigger character,
/// filters emoji from all packs available in the current room context, and
/// inserts the selected shortcode as `:shortcode: `.
class EmojiAutocompleteController extends ChangeNotifier {
  EmojiAutocompleteController({
    required this.textController,
    required this.stickerPackService,
    required this.room,
    this.debounceDuration = const Duration(milliseconds: 100),
  }) {
    textController.addListener(_onTextChanged);
  }

  final TextEditingController textController;
  final StickerPackService stickerPackService;
  final Room room;
  @visibleForTesting
  final Duration debounceDuration;

  Timer? _debounce;
  bool _isActive = false;
  bool _disposed = false;
  int _triggerOffset = -1;
  String _query = '';
  List<PackImage> _suggestions = [];
  int _selectedIndex = 0;

  bool get isActive => _isActive;
  String get query => _query;
  List<PackImage> get suggestions => _suggestions;
  int get selectedIndex => _selectedIndex;

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

    final textBeforeCursor = text.substring(0, cursorPos);
    final lastColon = textBeforeCursor.lastIndexOf(':');

    if (lastColon < 0) {
      _dismiss();
      return;
    }

    // Trigger must be at start of text or preceded by whitespace.
    if (lastColon > 0 &&
        text[lastColon - 1] != ' ' &&
        text[lastColon - 1] != '\n') {
      _dismiss();
      return;
    }

    final queryText = text.substring(lastColon + 1, cursorPos);

    // Query must not contain spaces or newlines.
    if (queryText.contains(' ') || queryText.contains('\n')) {
      _dismiss();
      return;
    }

    // Don't trigger on an already-closed shortcode (e.g. `:wave:`).
    if (queryText.endsWith(':')) {
      _dismiss();
      return;
    }

    _triggerOffset = lastColon;
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
    if (_disposed) return;
    final packs = stickerPackService.packsForRoom(room);
    final lowerQuery = _query.toLowerCase();

    final allEmoji = <PackImage>[
      for (final pack in packs) ...pack.emoji,
    ];

    if (lowerQuery.isEmpty) {
      _suggestions = allEmoji.take(20).toList();
    } else {
      _suggestions = allEmoji
          .where(
            (e) =>
                e.shortcode.toLowerCase().contains(lowerQuery) ||
                (e.body?.toLowerCase().contains(lowerQuery) ?? false),
          )
          .take(20)
          .toList();
    }

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

  void confirmSelection() {
    if (_suggestions.isEmpty) return;
    selectSuggestion(_suggestions[_selectedIndex]);
  }

  void selectSuggestion(PackImage emoji) {
    final text = textController.text;
    final before = text.substring(0, _triggerOffset);
    final cursorPos = textController.selection.baseOffset;
    final after = text.substring(cursorPos);
    final insertion = ':${emoji.shortcode}: ';
    textController.value = TextEditingValue(
      text: '$before$insertion$after',
      selection: TextSelection.collapsed(
        offset: before.length + insertion.length,
      ),
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
    _disposed = true;
    textController.removeListener(_onTextChanged);
    super.dispose();
  }
}
