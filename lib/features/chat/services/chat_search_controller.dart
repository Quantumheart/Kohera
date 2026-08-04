import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:kohera/features/chat/models/room_search_result.dart';
import 'package:kohera/features/chat/services/room_search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatSearchController extends ChangeNotifier {
  ChatSearchController({required this.roomId, required this.searchService});

  final String roomId;
  final RoomSearchService searchService;

  // ── Constants ──────────────────────────────────────────────
  static const minQueryLength = 2;
  static const _debounceDuration = Duration(milliseconds: 500);
  static const _maxRecentQueries = 10;

  // ── State ─────────────────────────────────────────────────
  bool _isSearching = false;
  bool get isSearching => _isSearching;

  List<RoomSearchResult> _results = [];
  List<RoomSearchResult> get results => _results;

  String? _nextBatch;
  String? get nextBatch => _nextBatch;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  String? _highlightedEventId;
  String? get highlightedEventId => _highlightedEventId;

  String _query = '';
  String get query => _query;

  int? _count;
  int? get count => _count;

  List<String>? _highlights;
  List<String>? get highlights => _highlights;

  bool _isEncryptedRoom = false;
  bool get isEncryptedRoom => _isEncryptedRoom;

  String? _senderFilter;
  String? get senderFilter => _senderFilter;

  void setSenderFilter(String? senderId) {
    _senderFilter = senderId;
    notifyListeners();
    if (_query.length >= minQueryLength) performSearch();
  }

  Set<String> get resultSenders {
    final senders = <String>{};
    for (final r in _results) {
      senders.add(r.message.senderId);
    }
    return senders;
  }

  List<String> _recentQueries = [];
  List<String> get recentQueries => _recentQueries;

  bool _disposed = false;

  Timer? _debounceTimer;
  Timer? _highlightTimer;

  // ── Actions ───────────────────────────────────────────────

  void open() {
    _loadRecentQueries();
    _isSearching = true;
    _results = [];
    _nextBatch = null;
    _error = null;
    _query = '';
    _count = null;
    _highlights = null;
    _isEncryptedRoom = false;
    _senderFilter = null;
    notifyListeners();
  }

  void close() {
    _debounceTimer?.cancel();
    _highlightTimer?.cancel();
    _highlightedEventId = null;
    _isSearching = false;
    _results = [];
    _nextBatch = null;
    _isLoading = false;
    _error = null;
    _query = '';
    _count = null;
    _highlights = null;
    _isEncryptedRoom = false;
    _senderFilter = null;
    notifyListeners();
  }

  void onQueryChanged(String text) {
    _debounceTimer?.cancel();
    _query = text.trim();

    if (_query.length < minQueryLength) {
      _results = [];
      _nextBatch = null;
      _error = null;
      _count = null;
      _highlights = null;
      _isEncryptedRoom = false;
      _senderFilter = null;
      notifyListeners();
      return;
    }

    notifyListeners();
    _debounceTimer = Timer(_debounceDuration, performSearch);
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
    }
    notifyListeners();

    try {
      debugPrint('[Kohera] Searching room for: $_query');
      final response = await searchService.search(
        roomId: roomId,
        query: _query,
        nextBatch: loadMore ? _nextBatch : null,
        senderFilter: _senderFilter,
      );

      if (_disposed) return;

      if (loadMore) {
        _results.addAll(response.results);
      } else {
        _results = response.results;
      }
      _nextBatch = response.nextBatch;
      _count = response.count;
      _highlights = response.highlights;
      _isEncryptedRoom = response.isEncryptedRoom;
      _isLoading = false;
      if (!loadMore) _saveRecentQuery();
      notifyListeners();
    } catch (e) {
      debugPrint('[Kohera] Search error: $e');
      if (_disposed) return;
      _isLoading = false;
      _error = 'Search failed. Please try again.';
      notifyListeners();
    }
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


  Future<void> _loadRecentQueries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('search_history_$roomId');
      if (json != null) {
        final list = jsonDecode(json) as List<dynamic>;
        _recentQueries = list.cast<String>();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[Kohera] Failed to load recent search queries: $e');
    }
  }

  void _saveRecentQuery() {
    if (_query.isEmpty) return;
    _recentQueries.remove(_query);
    _recentQueries.insert(0, _query);
    if (_recentQueries.length > _maxRecentQueries) {
      _recentQueries = _recentQueries.sublist(0, _maxRecentQueries);
    }
    unawaited(_persistRecentQueries());
  }

  Future<void> _persistRecentQueries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'search_history_$roomId',
        jsonEncode(_recentQueries),
      );
    } catch (e) {
      debugPrint('[Kohera] Failed to persist recent search queries: $e');
    }
  }

  Future<void> removeRecentQuery(String query) async {
    _recentQueries.remove(query);
    notifyListeners();
    await _persistRecentQueries();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _highlightTimer?.cancel();
    super.dispose();
  }
}
