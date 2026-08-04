import 'package:flutter/foundation.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/models/room_search_result.dart';
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
/// returns an empty [RoomSearchResponse] flagged `isEncryptedRoom: true`.
/// Encrypted search is handled separately (#897) — this placeholder keeps the
/// controller's contract uniform.
class RoomSearchService {
  RoomSearchService({required this.client});

  final Client client;

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

    // Encrypted rooms cannot be searched server-side yet (#897).
    if (room.encrypted) {
      return const RoomSearchResponse(isEncryptedRoom: true);
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
