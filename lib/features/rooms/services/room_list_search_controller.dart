import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/data/models/message_search_result.dart';
import 'package:kohera/data/repositories/message_search_repository.dart';

// ── Controller ──────────────────────────────────────────────
class RoomListSearchController extends ChangeNotifier {
  RoomListSearchController({required this.searchRepository});

  /// The search repository — the sole dependency.  All SDK interactions
  /// (server search, FTS5 index, timeline-scan fallback) and domain-model
  /// conversion happen behind this boundary.
  final MessageSearchRepository searchRepository;

  // ── Constants ──────────────────────────────────────────────
  static const _searchBatchLimit = 20;
  static const minQueryLength = 3;
  static const _debounceDuration = Duration(milliseconds: 500);

  // ── State ─────────────────────────────────────────────────
  List<MessageSearchResult> _results = [];
  List<MessageSearchResult> get results => List.unmodifiable(_results);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  String? _serverNextBatch;
  String? _indexNextBatch;

  /// Combined pagination token.  Non-null when either the server search
  /// or the index search has more results, signalling the UI to show
  /// "Load more".
  String? get nextBatch =>
      (_serverNextBatch != null || _indexNextBatch != null)
          ? (_serverNextBatch ?? _indexNextBatch)
          : null;

  int? _totalCount;
  int? get totalCount => _totalCount;

  String _query = '';
  String get query => _query;

  /// Encrypted rooms that are being indexed in the background.  The UI can
  /// surface an "indexing…" indicator for these rooms.
  Set<String> _indexingRoomIds = {};
  Set<String> get indexingRoomIds => Set.unmodifiable(_indexingRoomIds);

  bool _disposed = false;
  Timer? _debounceTimer;
  int _searchGeneration = 0;

  Set<String>? _scopeRoomIds;

  // ── Actions ───────────────────────────────────────────────

  void onQueryChanged(String text, {Set<String>? scopeRoomIds}) {
    _debounceTimer?.cancel();
    _query = text.trim();
    _scopeRoomIds = scopeRoomIds;

    if (_query.length < minQueryLength) {
      _results = [];
      _serverNextBatch = null;
      _indexNextBatch = null;
      _totalCount = null;
      _indexingRoomIds = {};
      _error = null;
      _isLoading = false;
      _searchGeneration++;
      if (!_disposed) notifyListeners();
      return;
    }

    _isLoading = true;
    if (!_disposed) notifyListeners();
    _debounceTimer = Timer(_debounceDuration, performSearch);
  }

  Future<void> performSearch({bool loadMore = false}) async {
    if (_disposed) return;
    if (_query.length < minQueryLength) return;

    final searchQuery = _query;
    final generation = ++_searchGeneration;

    _isLoading = true;
    _error = null;
    if (!loadMore) {
      _results = [];
      _serverNextBatch = null;
      _indexNextBatch = null;
      _totalCount = null;
      _indexingRoomIds = {};
    }
    notifyListeners();

    try {
      debugPrint('[Kohera] Searching messages for: $searchQuery');

      final scopeIds = _scopeRoomIds;

      // Run server search, index search, and fallback scan in parallel.
      // On loadMore, only paginate the server and index search — the
      // fallback scan runs once on the initial search.
      final serverFuture = searchRepository.searchServer(
        query: searchQuery,
        scopeRoomIds: scopeIds,
        nextBatch: loadMore ? _serverNextBatch : null,
        limit: _searchBatchLimit,
      );

      final indexFuture = searchRepository.searchLocal(
        query: searchQuery,
        scopeRoomIds: scopeIds,
        limit: _searchBatchLimit,
        offset: _parseOffset(loadMore ? _indexNextBatch : null),
      );

      final fallbackFuture = !loadMore
          ? searchRepository.searchUnindexed(
              query: searchQuery,
              scopeRoomIds: scopeIds,
              limit: _searchBatchLimit,
            )
          : Future.value(const UnindexedSearchResult());

      final results = await Future.wait([
        serverFuture,
        indexFuture,
        fallbackFuture,
      ]);

      if (_disposed || generation != _searchGeneration) return;

      final serverPage = results[0] as ServerSearchPage;
      final indexPage = results[1] as LocalSearchPage;
      final fallback = results[2] as UnindexedSearchResult;

      _serverNextBatch = serverPage.nextBatch;
      _indexNextBatch = indexPage.nextBatch;
      _indexingRoomIds = fallback.indexingRoomIds;

      // Total count: server + index + fallback.
      final serverCount = serverPage.count ?? 0;
      _totalCount = serverCount + indexPage.count + fallback.results.length;

      // Merge, deduplicate by eventId, and sort by timestamp descending.
      final merged = <String, MessageSearchResult>{};
      final previousResults = loadMore ? _results : <MessageSearchResult>[];
      for (final r in previousResults) {
        merged[r.eventId] = r;
      }
      for (final r in serverPage.results) {
        merged[r.eventId] = r;
      }
      for (final r in indexPage.results) {
        merged.putIfAbsent(r.eventId, () => r);
      }
      for (final r in fallback.results) {
        merged.putIfAbsent(r.eventId, () => r);
      }

      final sorted = merged.values.toList()
        ..sort((a, b) => b.originServerTs.compareTo(a.originServerTs));

      _results = sorted;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[Kohera] Message search error: $e');
      if (_disposed || generation != _searchGeneration) return;
      _isLoading = false;
      _error = 'Message search failed. The server may not support it.';
      notifyListeners();
    }
  }

  /// Parses an offset-based pagination token.
  static int _parseOffset(String? nextBatch) {
    if (nextBatch == null || nextBatch.isEmpty) return 0;
    return int.tryParse(nextBatch) ?? 0;
  }

  void clear() {
    _debounceTimer?.cancel();
    _searchGeneration++;
    _results = [];
    _serverNextBatch = null;
    _indexNextBatch = null;
    _totalCount = null;
    _indexingRoomIds = {};
    _isLoading = false;
    _error = null;
    _query = '';
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    super.dispose();
  }
}
