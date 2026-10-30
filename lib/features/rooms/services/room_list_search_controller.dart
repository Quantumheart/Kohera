import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/data/models/message_search_result.dart';
import 'package:kohera/data/repositories/message_search_repository.dart';

// ── Controller ──────────────────────────────────────────────
class RoomListSearchController extends ChangeNotifier {
  RoomListSearchController({required this.searchRepository});

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

  bool _serverExhausted = false;
  bool _indexExhausted = false;

  int _serverCount = 0;
  int _indexCount = 0;

  String? get nextBatch => _serverNextBatch ?? _indexNextBatch;

  int? _totalCount;
  int? get totalCount => _totalCount;

  String _query = '';
  String get query => _query;

  int _fallbackCount = 0;

  String? _partialError;
  String? get partialError => _partialError;

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
      _serverExhausted = false;
      _indexExhausted = false;
      _serverCount = 0;
      _indexCount = 0;
      _totalCount = null;
      _fallbackCount = 0;
      _partialError = null;
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
      _serverExhausted = false;
      _indexExhausted = false;
      _serverCount = 0;
      _indexCount = 0;
      _totalCount = null;
      _fallbackCount = 0;
      _partialError = null;
    }
    notifyListeners();

    try {
      debugPrint('[Kohera] Searching messages for: $searchQuery');

      final scopeIds = _scopeRoomIds;

      var serverFailed = false;
      var indexFailed = false;
      var fallbackFailed = false;

      final serverSkipped = _serverExhausted && loadMore;
      final indexSkipped = _indexExhausted && loadMore;

      final serverFuture = serverSkipped
          ? Future.value(const ServerSearchPage())
          : _guardSource(
              () => searchRepository.searchServer(
                query: searchQuery,
                scopeRoomIds: scopeIds,
                nextBatch: loadMore ? _serverNextBatch : null,
                limit: _searchBatchLimit,
              ),
              const ServerSearchPage(),
              () => serverFailed = true,
            );

      final indexFuture = indexSkipped
          ? Future.value(const LocalSearchPage())
          : _guardSource(
              () => searchRepository.searchLocal(
                query: searchQuery,
                scopeRoomIds: scopeIds,
                limit: _searchBatchLimit,
                offset: _parseOffset(loadMore ? _indexNextBatch : null),
              ),
              const LocalSearchPage(),
              () => indexFailed = true,
            );

      final fallbackFuture = !loadMore
          ? _guardSource(
              () => searchRepository.searchUnindexed(
                query: searchQuery,
                scopeRoomIds: scopeIds,
                limit: _searchBatchLimit,
                shouldAbort: () => generation != _searchGeneration,
              ),
              const UnindexedSearchResult(),
              () => fallbackFailed = true,
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

      if (!serverSkipped && !serverFailed) {
        _serverNextBatch = serverPage.nextBatch;
        _serverExhausted = serverPage.nextBatch == null;
        if (serverPage.count != null) _serverCount = serverPage.count!;
      }
      if (!indexSkipped && !indexFailed) {
        _indexNextBatch = indexPage.nextBatch;
        _indexExhausted = indexPage.nextBatch == null;
        if (indexPage.count != null) _indexCount = indexPage.count!;
      }

      if (!loadMore) {
        _fallbackCount = fallback.count;
      }

      _totalCount = _serverCount + _indexCount + _fallbackCount;

      final merged = <String, MessageSearchResult>{};
      final previousResults = loadMore ? _results : <MessageSearchResult>[];
      for (final r in previousResults) {
        merged[r.eventId] = r;
      }
      if (!serverFailed) {
        for (final r in serverPage.results) {
          merged[r.eventId] = r;
        }
      }
      if (!indexFailed) {
        for (final r in indexPage.results) {
          merged.putIfAbsent(r.eventId, () => r);
        }
      }
      if (!loadMore && !fallbackFailed) {
        for (final r in fallback.results) {
          merged.putIfAbsent(r.eventId, () => r);
        }
      }

      final sorted = merged.values.toList()
        ..sort((a, b) => b.originServerTs.compareTo(a.originServerTs));

      _results = sorted;
      _isLoading = false;

      _applyFailureState(
        serverFailed: serverFailed,
        indexFailed: indexFailed,
        fallbackFailed: fallbackFailed && !loadMore,
      );

      notifyListeners();
    } catch (e) {
      debugPrint('[Kohera] Message search error: $e');
      if (_disposed || generation != _searchGeneration) return;
      _isLoading = false;
      if (_results.isEmpty) {
        _error = 'Message search failed. The server may not support it.';
      }
      notifyListeners();
    }
  }

  Future<void> retry() => performSearch();

  void _applyFailureState({
    required bool serverFailed,
    required bool indexFailed,
    required bool fallbackFailed,
  }) {
    final failedSources = <String>[
      if (serverFailed) 'server',
      if (indexFailed) 'local index',
      if (fallbackFailed) 'unindexed rooms',
    ];

    final hardError = failedSources.length >= 3 ||
        (failedSources.isNotEmpty && _results.isEmpty);

    if (hardError) {
      _error = serverFailed
          ? 'Message search failed. The server may not support it.'
          : 'Message search failed.';
      _partialError = null;
    } else if (failedSources.isNotEmpty) {
      _partialError = 'Some results may be missing.';
      _error = null;
    } else {
      _partialError = null;
      _error = null;
    }
  }

  static int _parseOffset(String? nextBatch) {
    if (nextBatch == null || nextBatch.isEmpty) return 0;
    return int.tryParse(nextBatch) ?? 0;
  }

  static Future<T> _guardSource<T>(
    Future<T> Function() source,
    T defaultValue,
    void Function() markFailed,
  ) {
    try {
      return source().catchError((Object e) {
        markFailed();
        debugPrint('[Kohera] Search source failed: $e');
        return defaultValue;
      });
    } catch (e) {
      markFailed();
      debugPrint('[Kohera] Search source failed: $e');
      return Future.value(defaultValue);
    }
  }

  void clear() {
    _debounceTimer?.cancel();
    _searchGeneration++;
    _results = [];
    _serverNextBatch = null;
    _indexNextBatch = null;
    _serverExhausted = false;
    _indexExhausted = false;
    _serverCount = 0;
    _indexCount = 0;
    _totalCount = null;
    _fallbackCount = 0;
    _partialError = null;
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
