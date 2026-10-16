import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/utils/reply_fallback.dart';
import 'package:kohera/data/models/message_search_result.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:kohera/data/services/message_indexer_service.dart';
import 'package:kohera/data/services/message_search_database.dart';
import 'package:matrix/matrix.dart';

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

class UnindexedSearchResult {
  const UnindexedSearchResult({
    this.results = const [],
    this.count = 0,
    this.indexingRoomIds = const {},
  });

  final List<MessageSearchResult> results;
  final int count;
  final Set<String> indexingRoomIds;
}

class MessageSearchRepository {
  MessageSearchRepository({
    required MatrixClientService clientService,
    required MessageIndexerService indexer,
  })  : _clientService = clientService,
        _indexer = indexer;

  final MatrixClientService _clientService;
  final MessageIndexerService _indexer;

  Client get _client => _clientService.client;
  SearchIndex get _index => _indexer.database;

  // ── Server search (unencrypted rooms) ─────────────────────

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

  Future<LocalSearchPage> searchLocal({
    required String query,
    required int limit,
    Set<String>? scopeRoomIds,
    int offset = 0,
  }) async {
    if (!_index.isAvailable) return const LocalSearchPage();

    final matches = await _index.search(
      query: query,
      roomIds: scopeRoomIds,
      limit: limit,
      offset: offset,
    );

    final results = matches
        .map(_indexedMessageToResult)
        .whereType<MessageSearchResult>()
        .toList();

    final count = await _index.count(query: query, roomIds: scopeRoomIds);

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

  Future<UnindexedSearchResult> searchUnindexed({
    required String query,
    required int limit,
    Set<String>? scopeRoomIds,
    bool Function()? shouldAbort,
  }) async {
    final Set<String> indexedRooms;
    if (_index.isAvailable) {
      indexedRooms = await _index.indexedRoomIds();
    } else {
      indexedRooms = {};
    }

    final currentlyIndexing = _indexer.indexingRoomIds;

    var unindexed = _client.rooms.where((room) =>
        room.encrypted &&
        !indexedRooms.contains(room.id) &&
        !currentlyIndexing.contains(room.id));
    if (scopeRoomIds != null) {
      unindexed = unindexed.where((room) => scopeRoomIds.contains(room.id));
    }
    final unindexedRooms = unindexed.toList();
    if (unindexedRooms.isEmpty) return const UnindexedSearchResult();

    if (_index.isAvailable) {
      for (final room in unindexedRooms) {
        unawaited(_indexer.ensureRoomIndexed(room));
      }
    }

    debugPrint(
      '[Kohera] Timeline-scan fallback for ${unindexedRooms.length} '
      'unindexed encrypted rooms',
    );

    const batchSize = 5;
    final allResults = <MessageSearchResult>[];
    for (var i = 0; i < unindexedRooms.length; i += batchSize) {
      if (shouldAbort != null && shouldAbort()) {
        return UnindexedSearchResult(
          results: allResults,
          count: allResults.length,
          indexingRoomIds: unindexedRooms.map((r) => r.id).toSet(),
        );
      }
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
      count: allResults.length,
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

}
