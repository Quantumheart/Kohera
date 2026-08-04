import 'package:flutter/foundation.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/models/room_search_result.dart';
import 'package:kohera/features/chat/services/message_display_resolver.dart';
import 'package:matrix/matrix.dart';

class RoomSearchService {
  RoomSearchService({required this.client});

  final Client client;

  static const searchBatchLimit = 50;

  Future<RoomSearchResponse> search({
    required String roomId,
    required String query,
    String? nextBatch,
    int limit = searchBatchLimit,
  }) async {
    final room = client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found');

    if (room.encrypted) {
      return const RoomSearchResponse(
        results: [],
        isEncryptedRoom: true,
      );
    }

    return _searchServerSide(
      room: room,
      query: query,
      nextBatch: nextBatch,
      limit: limit,
    );
  }

  Future<RoomSearchResponse> _searchServerSide({
    required Room room,
    required String query,
    required String? nextBatch,
    required int limit,
  }) async {
    try {
      final result = await client.search(
        Categories(
          roomEvents: RoomEventsCriteria(
            searchTerm: query,
            keys: const [KeyKind.contentBody],
            orderBy: SearchOrder.recent,
            filter: SearchFilter(
              rooms: [room.id],
              limit: limit,
              types: const ['m.room.message'],
            ),
            eventContext: IncludeEventContext(
              beforeLimit: 3,
              afterLimit: 3,
              includeProfile: true,
            ),
          ),
        ),
        nextBatch: nextBatch,
      );

      final roomEvents = result.searchCategories.roomEvents;
      final rawResults = roomEvents?.results ?? [];
      const resolver = MessageDisplayResolver();

      final converted = <RoomSearchResult>[];
      for (final hit in rawResults) {
        final matchedEvent = hit.result;
        if (matchedEvent == null) continue;

        final event = Event.fromMatrixEvent(matchedEvent, room);
        final message = resolver(event);

        final contextBefore = <KoheraMessageDisplay>[];
        final contextAfter = <KoheraMessageDisplay>[];

        final context = hit.context;
        if (context != null) {
          for (final me in (context.eventsBefore ?? const <MatrixEvent>[])) {
            contextBefore.add(resolver(Event.fromMatrixEvent(me, room)));
          }
          for (final me in (context.eventsAfter ?? const <MatrixEvent>[])) {
            contextAfter.add(resolver(Event.fromMatrixEvent(me, room)));
          }
        }

        converted.add(RoomSearchResult(
          message: message,
          contextBefore: contextBefore,
          contextAfter: contextAfter,
          rank: hit.rank,
          isEncryptedRoom: false,
        ));
      }

      return RoomSearchResponse(
        results: converted,
        isEncryptedRoom: false,
        nextBatch: roomEvents?.nextBatch,
        count: roomEvents?.count,
        highlights: roomEvents?.highlights,
      );
    } catch (e) {
      debugPrint('[Kohera] Server search failed: $e');
      rethrow;
    }
  }
}
