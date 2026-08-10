import 'package:flutter/foundation.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/models/room_search_result.dart';
import 'package:kohera/features/chat/services/local_search_service.dart';
import 'package:kohera/features/chat/services/message_display_resolver.dart';
import 'package:matrix/matrix.dart';

/// Searches a single Matrix room's messages via the server-side `v3/search`
/// API (`client.search()`).
///
/// For **unencrypted** rooms this issues a real server search restricted to
/// the room and `m.room.message` events, requesting 3 events of context on
/// each side plus sender profile info. Each [Result] is converted to a
/// [RoomSearchResult] via [Event.fromMatrixEvent] + [MessageDisplayResolver].
///
/// For **encrypted** rooms the server cannot index message bodies, so this
/// delegates to [LocalSearchService] when one is available (i.e. the on-device
/// FTS5 index is present). When no local index is available (e.g. on web), an
/// empty [RoomSearchResponse] flagged `isEncryptedRoom: true` is returned so
/// the UI can show the platform-specific "not available" message.
class RoomSearchService {
  RoomSearchService({required this.client, this.localSearchService});

  final Client client;

  /// Optional local (FTS5) search backend for encrypted rooms. `null` when the
  /// platform does not support the local search index.
  final LocalSearchService? localSearchService;

  /// Number of context events to request before and after each match.
  static const contextBeforeLimit = 3;
  static const contextAfterLimit = 3;

  /// Searches [roomId] for [searchTerm].
  ///
  /// Pass [nextBatch] to paginate a previous response. [limit] caps the
  /// number of matches returned in a single page.
  Future<RoomSearchResponse> search({
    required String roomId,
    required String searchTerm,
    required int limit,
    String? nextBatch,
  }) async {
    final room = client.getRoomById(roomId);
    if (room == null) {
      return const RoomSearchResponse();
    }

    // Encrypted rooms cannot be searched server-side; route to the local FTS5
    // index when available, otherwise return an empty encrypted-room response
    // so the UI can show the platform-specific message.
    if (room.encrypted) {
      final local = localSearchService;
      if (local == null) {
        return const RoomSearchResponse(isEncryptedRoom: true);
      }
      return local.search(
        roomId: roomId,
        query: searchTerm,
        nextBatch: nextBatch,
        limit: limit,
      );
    }

    try {
      final searchResults = await client.search(
        Categories(
          roomEvents: RoomEventsCriteria(
            searchTerm: searchTerm,
            keys: [KeyKind.contentBody],
            orderBy: SearchOrder.recent,
            filter: SearchFilter(
              rooms: [roomId],
              limit: limit,
              types: ['m.room.message'],
            ),
            eventContext: IncludeEventContext(
              beforeLimit: contextBeforeLimit,
              afterLimit: contextAfterLimit,
              includeProfile: true,
            ),
          ),
        ),
        nextBatch: nextBatch,
      );

      final roomEvents = searchResults.searchCategories.roomEvents;
      if (roomEvents == null) {
        return const RoomSearchResponse();
      }

      const resolver = MessageDisplayResolver();
      final results = <RoomSearchResult>[];
      for (final result in roomEvents.results ?? <Result>[]) {
        final matrixEvent = result.result;
        if (matrixEvent == null) continue;

        final event = Event.fromMatrixEvent(matrixEvent, room);
        final message = resolver(event);

        final context = result.context;
        final before = _resolveContext(
          context?.eventsBefore,
          room,
          resolver,
        );
        final after = _resolveContext(
          context?.eventsAfter,
          room,
          resolver,
        );

        results.add(RoomSearchResult(
          message: message,
          contextBefore: before,
          contextAfter: after,
          rank: result.rank,
        ));
      }

      return RoomSearchResponse(
        results: results,
        nextBatch: roomEvents.nextBatch,
        count: roomEvents.count,
        highlights: roomEvents.highlights,
      );
    } catch (e) {
      debugPrint('[Kohera] Room search error: $e');
      rethrow;
    }
  }

  static List<KoheraMessageDisplay> _resolveContext(
    List<MatrixEvent>? events,
    Room room,
    MessageDisplayResolver resolver,
  ) {
    if (events == null || events.isEmpty) return const [];
    return events
        .map((me) => resolver(Event.fromMatrixEvent(me, room)))
        .toList(growable: false);
  }
}
