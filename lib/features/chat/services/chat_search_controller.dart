import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:kohera/features/chat/models/room_search_result.dart';
import 'package:kohera/features/chat/services/message_indexer_service.dart';
import 'package:kohera/features/chat/services/room_search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatSearchController extends ChangeNotifier {
  ChatSearchController({
    required this.roomId,
    required this.searchService,
    this.messageIndexer,
  });

  final String roomId;
  final RoomSearchService searchService;
  final MessageIndexerService? messageIndexer;

  // ── Constants ──────────────────────────────────────────────
  static const searchBatchLimit = 50;
  static const minQueryLength = 2;
  static const _debounceDuration = Duration(milliseconds: 500);
  static const _maxRecentQueries = 10;
  static const _historyKeyPrefix = 'search_history_';

  // ── State ─────────────────────────────────────────────────
  bool _isSearching = false;
  bool get isSearching => _isSearching;

  List<RoomSearchResult> _results = [];
  List<RoomSearchResult> get results => _results;

  String? _nextBatch;
  String? get nextBatch => _nextBatch;

  int? _count;
  int? get count => _count;

  List<String>? _highlights;
  List<String>? get highlights => _highlights;

  bool _isEncryptedRoom = false;
  bool get isEncryptedRoom => _isEncryptedRoom;

  bool _hasLocalIndex = false;
  bool get hasLocalIndex => _hasLocalIndex;

  /// `true` when the local FTS5 index for this room is still being built
  /// (background backfill in progress). The UI shows an "indexing…" hint.
  bool _isIndexingRoom = false;
  bool get isIndexingRoom => _isIndexingRoom;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  String? _highlightedEventId;
  String? get highlightedEventId => _highlightedEventId;

  String _query = '';
  String get query => _query;

  /// Sender ID filter, or `null` for "all senders".
  String? _senderFilter;
  String? get senderFilter => _senderFilter;

  /// Date range filter, or `null` for "all dates".
  DateTimeRange? _dateRange;
  DateTimeRange? get dateRange => _dateRange;

  /// `true` when either the sender or date range filter is active.
  bool get hasActiveFilters => _senderFilter != null || _dateRange != null;

  /// Recent search queries for this room, most-recent first.
  List<String> _recentQueries = [];
  List<String> get recentQueries => List.unmodifiable(_recentQueries);

  /// Index of the keyboard-selected result in [_results], or -1 when no
  /// result is selected. Reset to 0 whenever new results arrive.
  int _selectedIndex = -1;
  int get selectedIndex => _selectedIndex;

  bool _disposed = false;

  Timer? _debounceTimer;
  Timer? _highlightTimer;

  // ── Actions ───────────────────────────────────────────────

  void open() {
    _isSearching = true;
    messageIndexer?.addListener(_onIndexerChanged);
    _updateIndexingState();
    _results = [];
    _nextBatch = null;
    _count = null;
    _highlights = null;
    _isEncryptedRoom = false;
    _hasLocalIndex = false;
    _error = null;
    _query = '';
    _selectedIndex = -1;
    _senderFilter = null;
    _dateRange = null;
    _recentQueries = [];
    unawaited(_loadRecentQueries());
    notifyListeners();
  }

  void close() {
    messageIndexer?.removeListener(_onIndexerChanged);
    _debounceTimer?.cancel();
    _highlightTimer?.cancel();
    _highlightedEventId = null;
    _isSearching = false;
    _results = [];
    _nextBatch = null;
    _count = null;
    _highlights = null;
    _isEncryptedRoom = false;
    _hasLocalIndex = false;
    _isLoading = false;
    _error = null;
    _query = '';
    _selectedIndex = -1;
    _isIndexingRoom = false;
    _senderFilter = null;
    _dateRange = null;
    notifyListeners();
  }

  void onQueryChanged(String text) {
    _debounceTimer?.cancel();
    _query = text.trim();

    if (_query.length < minQueryLength) {
      _results = [];
      _nextBatch = null;
      _count = null;
      _highlights = null;
      _isEncryptedRoom = false;
      _hasLocalIndex = false;
      _error = null;
      _selectedIndex = -1;
      notifyListeners();
      return;
    }

    notifyListeners();
    _debounceTimer = Timer(_debounceDuration, performSearch);
  }

  /// Sets the sender filter and re-triggers the search.
  /// Pass `null` to clear the sender filter.
  set senderFilter(String? value) {
    if (_senderFilter == value) return;
    _senderFilter = value;
    notifyListeners();
    if (_query.length >= minQueryLength) {
      unawaited(performSearch());
    }
  }

  /// Sets the date range filter and re-triggers the search.
  /// Pass `null` to clear the date range filter.
  set dateRange(DateTimeRange? value) {
    if (_dateRange == value) return;
    _dateRange = value;
    notifyListeners();
    if (_query.length >= minQueryLength) {
      unawaited(performSearch());
    }
  }

  /// Clears both the sender and date range filters, then re-triggers the
  /// search.
  void clearFilters() {
    if (_senderFilter == null && _dateRange == null) return;
    _senderFilter = null;
    _dateRange = null;
    notifyListeners();
    if (_query.length >= minQueryLength) {
      unawaited(performSearch());
    }
  }

  Future<void> performSearch({bool loadMore = false}) async {
    if (_query.length < minQueryLength) return;

    _isLoading = true;
    _error = null;
    if (!loadMore) {
      _results = [];
      _nextBatch = null;
      _count = null;
      _highlights = null;
      _isEncryptedRoom = false;
      _hasLocalIndex = false;
      _selectedIndex = -1;
    }
    notifyListeners();

    try {
      debugPrint('[Kohera] Searching room for: $_query');
      final nextBatch = loadMore ? _nextBatch : null;
      final response = await searchService.search(
        roomId: roomId,
        searchTerm: _query,
        limit: searchBatchLimit,
        nextBatch: nextBatch,
        senderId: _senderFilter,
        dateRange: _dateRange,
      );

      if (_disposed) return;

      _isEncryptedRoom = response.isEncryptedRoom;
      _hasLocalIndex = response.hasLocalIndex;
      _count = response.count;
      _highlights = response.highlights;

      if (loadMore) {
        _results.addAll(response.results);
      } else {
        _results = response.results;
        // Persist the query to recent history on a successful fresh search.
        _addToRecentQueries(_query);
      }
      _nextBatch = response.nextBatch;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[Kohera] Search error: $e');
      if (_disposed) return;
      _isLoading = false;
      _error = 'Search failed. Please try again.';
      notifyListeners();
    }
  }

  void _onIndexerChanged() {
    if (_disposed) return;
    _updateIndexingState();
  }

  void _updateIndexingState() {
    final indexer = messageIndexer;
    if (indexer == null) return;
    final wasIndexing = _isIndexingRoom;
    _isIndexingRoom = indexer.isIndexing &&
        indexer.indexingProgressFor(roomId) != null;
    if (wasIndexing != _isIndexingRoom) {
      notifyListeners();
    }
  }

  /// Moves the keyboard selection down by one result (clamped to last).
  void navigateDown() {
    if (_results.isEmpty) return;
    _selectedIndex = (_selectedIndex + 1).clamp(0, _results.length - 1);
    notifyListeners();
  }

  /// Moves the keyboard selection up by one result (clamped to 0).
  void navigateUp() {
    if (_results.isEmpty) return;
    _selectedIndex = (_selectedIndex - 1).clamp(0, _results.length - 1);
    notifyListeners();
  }

  void setHighlight(String eventId) {
    _highlightTimer?.cancel();
    _highlightedEventId = eventId;
    notifyListeners();

    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (_disposed) return;
      _highlightedEventId = null;
      notifyListeners();
    });
  }

  // ── Recent query persistence ──────────────────────────────

  /// Adds [query] to the front of [_recentQueries], deduplicating and
  /// trimming to [_maxRecentQueries]. Persists asynchronously.
  void _addToRecentQueries(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _recentQueries.remove(trimmed);
    _recentQueries.insert(0, trimmed);
    if (_recentQueries.length > _maxRecentQueries) {
      _recentQueries = _recentQueries.sublist(0, _maxRecentQueries);
    }
    unawaited(_saveRecentQueries());
  }

  /// Removes [query] from [_recentQueries] and persists the change.
  void removeRecentQuery(String query) {
    if (_recentQueries.remove(query)) {
      unawaited(_saveRecentQueries());
      notifyListeners();
    }
  }

  /// Loads recent queries from [SharedPreferences] for this room.
  Future<void> _loadRecentQueries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('$_historyKeyPrefix$roomId');
      if (json != null) {
        final list = jsonDecode(json);
        if (list is List) {
          _recentQueries = list.cast<String>();
          if (!_disposed) notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[Kohera] Failed to load recent search queries: $e');
    }
  }

  /// Persists [_recentQueries] to [SharedPreferences] for this room.
  Future<void> _saveRecentQueries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_historyKeyPrefix$roomId',
        jsonEncode(_recentQueries),
      );
    } catch (e) {
      debugPrint('[Kohera] Failed to save recent search queries: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _highlightTimer?.cancel();
    super.dispose();
  }
}
