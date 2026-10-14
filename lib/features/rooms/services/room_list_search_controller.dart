import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/utils/reply_fallback.dart';
import 'package:kohera/data/services/message_search_database.dart';
import 'package:matrix/matrix.dart';

// ── Data class ──────────────────────────────────────────────
class MessageSearchResult {
  const MessageSearchResult({
    required this.roomId,
    required this.roomName,
    required this.senderName,
    required this.senderId,
    required this.body,
    required this.eventId,
    required this.originServerTs,
  });

  final String roomId;
  final String roomName;
  final String senderName;
  final String senderId;
  final String body;
  final String eventId;
  final DateTime originServerTs;
}

/// Outcome of a single index (FTS5) search page.
class _IndexSearchOutcome {
  const _IndexSearchOutcome({
    required this.results,
    required this.count,
    required this.nextBatch,
  });

  final List<MessageSearchResult> results;
  final int count;
  final String? nextBatch;
}

// ── Controller ──────────────────────────────────────────────
class RoomListSearchController extends ChangeNotifier {
  RoomListSearchController({
    required this.getClient,
    required this.searchIndex,
    this.ensureRoomIndexed,
  });

  final Client Function() getClient;

  /// The local FTS5 search index.  When available, global encrypted-room
  /// search is a single unscoped query (`roomId: null`) instead of a
  /// per-room timeline fan-out, so cost is O(1) regardless of how many
  /// encrypted rooms exist.
  final SearchIndex searchIndex;

  /// Lazily indexes a room's history in the background.  Called for
  /// encrypted rooms that are not yet indexed so future searches include
  /// them.
  final Future<void> Function(Room room)? ensureRoomIndexed;

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

    final client = getClient();
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

      // Server search (unencrypted rooms) — paginated via server nextBatch.
      final serverFuture = client.search(
        Categories(
          roomEvents: RoomEventsCriteria(
            searchTerm: searchQuery,
            orderBy: SearchOrder.recent,
            keys: [KeyKind.contentBody],
            filter: SearchFilter(
              types: ['m.room.message'],
              limit: _searchBatchLimit,
              rooms: scopeIds?.toList(),
            ),
            eventContext: IncludeEventContext(afterLimit: 0, beforeLimit: 0),
          ),
        ),
        nextBatch: loadMore ? _serverNextBatch : null,
      );

      // Index search (encrypted rooms) — paginated via offset.
      final indexFuture = _searchIndex(
        query: searchQuery,
        scopeRoomIds: scopeIds,
        loadMore: loadMore,
      );

      // Fallback timeline scan for encrypted rooms not yet indexed.
      // Only on the initial search — the scan is bounded per room and
      // not paginated.  Also triggers lazy indexing so future searches
      // include these rooms via the index.
      final fallbackFuture = !loadMore
          ? _searchUnindexedRooms(client, searchQuery, scopeRoomIds: scopeIds)
          : Future<List<MessageSearchResult>>.value(const []);

      final results = await Future.wait([
        serverFuture,
        indexFuture,
        fallbackFuture,
      ]);

      if (_disposed || generation != _searchGeneration) return;

      final response = results[0] as SearchResults;
      final indexOutcome = results[1] as _IndexSearchOutcome;
      final fallbackResults = results[2] as List<MessageSearchResult>;

      // Parse server results.
      final serverResults = <MessageSearchResult>[];
      final roomEvents = response.searchCategories.roomEvents;

      if (roomEvents != null) {
        for (final result in roomEvents.results ?? <Result>[]) {
          final event = result.result;
          if (event == null) continue;
          final roomId = event.roomId;
          if (roomId == null) continue;

          final rawBody = event.content.tryGet<String>('body');
          if (rawBody == null || rawBody.isEmpty) continue;

          final room = client.getRoomById(roomId);
          final roomName = room?.getLocalizedDisplayname() ?? roomId;
          final senderName = room
                  ?.unsafeGetUserFromMemoryOrFallback(event.senderId)
                  .displayName ??
              event.senderId;

          serverResults.add(MessageSearchResult(
            roomId: roomId,
            roomName: roomName,
            senderName: senderName,
            senderId: event.senderId,
            body: stripReplyFallback(rawBody),
            eventId: event.eventId,
            originServerTs: event.originServerTs,
          ),);
        }

        _serverNextBatch = roomEvents.nextBatch;
      }

      // Update index pagination.
      _indexNextBatch = indexOutcome.nextBatch;

      // Total count: server + index + fallback.
      final serverCount = roomEvents?.count ?? 0;
      _totalCount = serverCount + indexOutcome.count + fallbackResults.length;

      // Merge, deduplicate by eventId, and sort by timestamp descending.
      final merged = <String, MessageSearchResult>{};
      final previousResults = loadMore ? _results : <MessageSearchResult>[];
      for (final r in previousResults) {
        merged[r.eventId] = r;
      }
      for (final r in serverResults) {
        merged[r.eventId] = r;
      }
      for (final r in indexOutcome.results) {
        merged.putIfAbsent(r.eventId, () => r);
      }
      for (final r in fallbackResults) {
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

  /// Searches the FTS5 index with a single unscoped query (`roomId: null`)
  /// that spans every indexed (encrypted) room at once.  When a space scope
  /// is active, results are post-filtered client-side because the index has
  /// no multi-room filter.
  Future<_IndexSearchOutcome> _searchIndex({
    required String query,
    required bool loadMore,
    Set<String>? scopeRoomIds,
  }) async {
    if (!searchIndex.isAvailable) {
      return const _IndexSearchOutcome(results: [], count: 0, nextBatch: null);
    }

    final client = getClient();
    final offset = _parseOffset(loadMore ? _indexNextBatch : null);

    final matches = await searchIndex.search(
      query: query,
      limit: _searchBatchLimit,
      offset: offset,
    );

    // Post-filter by scope when a space is selected.
    final scopedMatches = scopeRoomIds != null
        ? matches.where((m) => scopeRoomIds.contains(m.roomId)).toList()
        : matches;

    final results = scopedMatches
        .map((m) => _indexedMessageToResult(m, client))
        .whereType<MessageSearchResult>()
        .toList();

    // Count: one unscoped COUNT for global search; for scoped search,
    // sum per-room counts for encrypted indexed rooms in scope (bounded
    // by scope size).
    final int count;
    if (scopeRoomIds != null) {
      final indexed = await searchIndex.indexedRoomIds();
      final scopedEncryptedIndexed = client.rooms
          .where((r) =>
              r.encrypted &&
              scopeRoomIds.contains(r.id) &&
              indexed.contains(r.id))
          .map((r) => r.id)
          .toSet();
      var sum = 0;
      for (final roomId in scopedEncryptedIndexed) {
        sum += await searchIndex.count(roomId: roomId, query: query);
      }
      count = sum;
    } else {
      count = await searchIndex.count(query: query);
    }

    // Encode next offset only when the unfiltered page was full.
    final nextOffset = matches.length < _searchBatchLimit
        ? null
        : (offset + matches.length).toString();

    return _IndexSearchOutcome(
      results: results,
      count: count,
      nextBatch: nextOffset,
    );
  }

  /// Timeline-scan fallback for encrypted rooms that have not been indexed
  /// yet.  Also triggers lazy background indexing via [ensureRoomIndexed]
  /// so subsequent searches include these rooms via the FTS5 index.
  Future<List<MessageSearchResult>> _searchUnindexedRooms(
    Client client,
    String query, {
    Set<String>? scopeRoomIds,
  }) async {
    if (!searchIndex.isAvailable) return const [];

    final indexedRooms = await searchIndex.indexedRoomIds();

    var unindexed = client.rooms.where((room) =>
        room.encrypted && !indexedRooms.contains(room.id));
    if (scopeRoomIds != null) {
      unindexed = unindexed.where((room) => scopeRoomIds.contains(room.id));
    }
    final unindexedRooms = unindexed.toList();
    if (unindexedRooms.isEmpty) return const [];

    // Track which rooms are being indexed so the UI can surface progress.
    _indexingRoomIds = unindexedRooms.map((r) => r.id).toSet();

    // Trigger lazy indexing for these rooms.
    final ensure = ensureRoomIndexed;
    if (ensure != null) {
      for (final room in unindexedRooms) {
        unawaited(ensure(room));
      }
    }

    debugPrint(
      '[Kohera] Timeline-scan fallback for ${unindexedRooms.length} '
      'unindexed encrypted rooms',
    );

    // Search rooms in batches to avoid excessive concurrent DB queries.
    const batchSize = 5;
    final allResults = <MessageSearchResult>[];
    for (var i = 0; i < unindexedRooms.length; i += batchSize) {
      if (_disposed) return allResults;
      final batch = unindexedRooms.sublist(
        i,
        i + batchSize > unindexedRooms.length
            ? unindexedRooms.length
            : i + batchSize,
      );
      final batchResults = await Future.wait(batch.map((room) async {
        try {
          final result = await room.searchEvents(
            searchTerm: query,
            limit: _searchBatchLimit,
          );
          return result.events
              .where((event) =>
                  event.type == EventTypes.Message &&
                  (event.content.tryGet<String>('body')?.isNotEmpty ?? false))
              .map((event) {
                final rawBody = event.content.tryGet<String>('body') ?? '';
                return MessageSearchResult(
                  roomId: room.id,
                  roomName: room.getLocalizedDisplayname(),
                  senderName: room
                      .unsafeGetUserFromMemoryOrFallback(event.senderId)
                      .displayName ?? event.senderId,
                  senderId: event.senderId,
                  body: stripReplyFallback(rawBody),
                  eventId: event.eventId,
                  originServerTs: event.originServerTs,
                );
              })
              .toList();
        } catch (e) {
          debugPrint(
            '[Kohera] Timeline-scan fallback failed for ${room.id}: $e',
          );
          return <MessageSearchResult>[];
        }
      }),);
      allResults.addAll(batchResults.expand((list) => list));
    }
    return allResults;
  }

  /// Converts an [IndexedMessage] from the FTS5 index to a
  /// [MessageSearchResult] for the room list.
  MessageSearchResult? _indexedMessageToResult(
    IndexedMessage msg,
    Client client,
  ) {
    final room = client.getRoomById(msg.roomId);
    if (room == null) return null;

    final senderName = room
            .unsafeGetUserFromMemoryOrFallback(msg.senderId)
            .displayName ??
        msg.senderId;

    return MessageSearchResult(
      roomId: msg.roomId,
      roomName: room.getLocalizedDisplayname(),
      senderName: senderName,
      senderId: msg.senderId,
      body: stripReplyFallback(msg.body),
      eventId: msg.eventId,
      originServerTs: msg.originServerTs,
    );
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
