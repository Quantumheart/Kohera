import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/utils/reply_fallback.dart';
import 'package:kohera/data/models/message_search_result.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:kohera/data/services/message_indexer_service.dart';
import 'package:kohera/data/services/message_search_database.dart';
import 'package:matrix/matrix.dart';

/// The outcome of a single server search page.
class ServerSearchPage {
  const ServerSearchPage({
    this.results = const [],
    this.count,
    this.nextBatch,
  });

  final List<MessageSearchResult> results;
  final int? count;
  final String? nextBatch;
}

/// The outcome of a single local FTS5 index search page.
class LocalSearchPage {
  const LocalSearchPage({
    this.results = const [],
    this.count = 0,
    this.nextBatch,
  });

  final List<MessageSearchResult> results;
  final int count;
  final String? nextBatch;
}

/// The outcome of the timeline-scan fallback for unindexed encrypted rooms.
class UnindexedSearchResult {
  const UnindexedSearchResult({
    this.results = const [],
    this.indexingRoomIds = const {},
  });

  final List<MessageSearchResult> results;

  /// Encrypted room IDs that were not yet indexed and have been submitted
  /// for background indexing via [MessageIndexerService.ensureRoomIndexed].
  final Set<String> indexingRoomIds;
}

/// Repository boundary for global (cross-room) message search.
///
/// Wraps [MessageIndexerService] (the FTS5 search index) and
/// [MatrixClientService] (the SDK boundary) so that feature-layer
/// controllers consume [MessageSearchResult]s without touching
/// `SearchIndex`, `IndexedMessage`, `Client`, or `Room` directly.
///
/// Three search sources are unified here:
///
/// 1. **Server search** ([searchServer]) — the `v3/search` endpoint for
///    unencrypted rooms.
/// 2. **Index search** ([searchLocal]) — one unscoped FTS5 query at
///    `roomId: null` that spans every indexed (encrypted) room at once.
/// 3. **Fallback scan** ([searchUnindexed]) — a bounded timeline scan for
///    encrypted rooms that have not been indexed yet, which also triggers
///    lazy background indexing.
class MessageSearchRepository extends ChangeNotifier {
  MessageSearchRepository({
    required MatrixClientService clientService,
    required MessageIndexerService indexer,
  })  : _clientService = clientService,
        _indexer = indexer {
    _indexer.addListener(_onIndexerChanged);
  }

  final MatrixClientService _clientService;
  final MessageIndexerService _indexer;

  Client get _client => _clientService.client;
  SearchIndex get _index => _indexer.database;

  bool _disposed = false;

  void _onIndexerChanged() {
    if (!_disposed) notifyListeners();
  }

  // ── Server search (unencrypted rooms) ─────────────────────

  /// Searches the homeserver's `v3/search` endpoint for [query],
  /// optionally narrowed to [scopeRoomIds].  Paginated via [nextBatch].
  Future<ServerSearchPage> searchServer({
    required String query,
    required int limit,
    Set<String>? scopeRoomIds,
    String? nextBatch,
  }) async {
    final response = await _client.search(
      Categories(
        roomEvents: RoomEventsCriteria(
          searchTerm: query,
          orderBy: SearchOrder.recent,
          keys: [KeyKind.contentBody],
          filter: SearchFilter(
            types: ['m.room.message'],
            limit: limit,
            rooms: scopeRoomIds?.toList(),
          ),
          eventContext: IncludeEventContext(afterLimit: 0, beforeLimit: 0),
        ),
      ),
      nextBatch: nextBatch,
    );

    final roomEvents = response.searchCategories.roomEvents;
    if (roomEvents == null) return const ServerSearchPage();

    final results = <MessageSearchResult>[];
    for (final result in roomEvents.results ?? <Result>[]) {
      final event = result.result;
      if (event == null) continue;
      final roomId = event.roomId;
      if (roomId == null) continue;

      final rawBody = event.content.tryGet<String>('body');
      if (rawBody == null || rawBody.isEmpty) continue;

      final room = _client.getRoomById(roomId);
      final roomName = room?.getLocalizedDisplayname() ?? roomId;
      final senderName =
          room?.unsafeGetUserFromMemoryOrFallback(event.senderId).displayName ??
              event.senderId;

      results.add(MessageSearchResult(
        roomId: roomId,
        roomName: roomName,
        senderName: senderName,
        senderId: event.senderId,
        body: stripReplyFallback(rawBody),
        eventId: event.eventId,
        originServerTs: event.originServerTs,
      ),);
    }

    return ServerSearchPage(
      results: results,
      count: roomEvents.count,
      nextBatch: roomEvents.nextBatch,
    );
  }

  // ── Local FTS5 index search (encrypted rooms) ────────────

  /// Searches the FTS5 index with a single unscoped query (`roomId: null`)
  /// that spans every indexed room at once.  When [scopeRoomIds] is set,
  /// results are post-filtered client-side because the index has no
  /// multi-room filter.
  Future<LocalSearchPage> searchLocal({
    required String query,
    required int limit,
    Set<String>? scopeRoomIds,
    int offset = 0,
  }) async {
    if (!_index.isAvailable) return const LocalSearchPage();

    final matches = await _index.search(
      query: query,
      limit: limit,
      offset: offset,
    );

    // Post-filter by scope when a space is selected.
    final scopedMatches = scopeRoomIds != null
        ? matches.where((m) => scopeRoomIds.contains(m.roomId)).toList()
        : matches;

    final results = scopedMatches
        .map(_indexedMessageToResult)
        .whereType<MessageSearchResult>()
        .toList();

    // Count: one unscoped COUNT for global search; for scoped search,
    // sum per-room counts for encrypted indexed rooms in scope (bounded
    // by scope size).
    final int count;
    if (scopeRoomIds != null) {
      final indexed = await _index.indexedRoomIds();
      final scopedEncryptedIndexed = _client.rooms
          .where((r) =>
              r.encrypted &&
              scopeRoomIds.contains(r.id) &&
              indexed.contains(r.id))
          .map((r) => r.id)
          .toSet();
      var sum = 0;
      for (final roomId in scopedEncryptedIndexed) {
        sum += await _index.count(roomId: roomId, query: query);
      }
      count = sum;
    } else {
      count = await _index.count(query: query);
    }

    // Encode next offset only when the unfiltered page was full.
    final nextOffset = matches.length < limit
        ? null
        : (offset + matches.length).toString();

    return LocalSearchPage(
      results: results,
      count: count,
      nextBatch: nextOffset,
    );
  }

  // ── Fallback timeline scan (unindexed encrypted rooms) ────

  /// Scans the local timeline of encrypted rooms that have not been
  /// indexed yet.  Also triggers lazy background indexing via
  /// [MessageIndexerService.ensureRoomIndexed] so subsequent searches
  /// include these rooms via the FTS5 index.
  Future<UnindexedSearchResult> searchUnindexed({
    required String query,
    required int limit,
    Set<String>? scopeRoomIds,
  }) async {
    if (!_index.isAvailable) return const UnindexedSearchResult();

    final indexedRooms = await _index.indexedRoomIds();

    var unindexed = _client.rooms
        .where((room) => room.encrypted && !indexedRooms.contains(room.id));
    if (scopeRoomIds != null) {
      unindexed = unindexed.where((room) => scopeRoomIds.contains(room.id));
    }
    final unindexedRooms = unindexed.toList();
    if (unindexedRooms.isEmpty) return const UnindexedSearchResult();

    // Trigger lazy indexing and track which rooms are being indexed.
    for (final room in unindexedRooms) {
      unawaited(_indexer.ensureRoomIndexed(room));
    }

    debugPrint(
      '[Kohera] Timeline-scan fallback for ${unindexedRooms.length} '
      'unindexed encrypted rooms',
    );

    // Search rooms in batches to avoid excessive concurrent DB queries.
    const batchSize = 5;
    final allResults = <MessageSearchResult>[];
    for (var i = 0; i < unindexedRooms.length; i += batchSize) {
      if (_disposed) break;
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
            limit: limit,
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
                          .displayName ??
                      event.senderId,
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

    return UnindexedSearchResult(
      results: allResults,
      indexingRoomIds: unindexedRooms.map((r) => r.id).toSet(),
    );
  }

  // ── Conversion helpers ────────────────────────────────────

  MessageSearchResult? _indexedMessageToResult(IndexedMessage msg) {
    final room = _client.getRoomById(msg.roomId);
    if (room == null) return null;

    final senderName =
        room.unsafeGetUserFromMemoryOrFallback(msg.senderId).displayName ??
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

  @override
  void dispose() {
    _disposed = true;
    _indexer.removeListener(_onIndexerChanged);
    super.dispose();
  }
}
