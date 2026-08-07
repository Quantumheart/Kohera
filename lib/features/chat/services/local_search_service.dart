import 'dart:math' as math;

import 'package:kohera/core/utils/reply_fallback.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/models/kohera_message_status.dart';
import 'package:kohera/features/chat/models/room_search_result.dart';
import 'package:kohera/features/chat/services/message_display_resolver.dart';
import 'package:kohera/features/chat/services/message_search_database.dart';
import 'package:matrix/matrix.dart';

/// Searches a single encrypted Matrix room's messages using a local FTS5 index.
///
/// Falls back to an empty response when the index is unavailable, keeping the
/// caller's contract identical to [RoomSearchService]. Results include up to
/// three surrounding events for context, loaded from the local event store.
class LocalSearchService {
  LocalSearchService({required this.client, required this.database});

  final Client client;
  final MessageSearchDatabase database;

  static const contextBeforeLimit = 3;
  static const contextAfterLimit = 3;

  Future<RoomSearchResponse> search({
    required String roomId,
    required String query,
    required int limit,
    String? nextBatch,
  }) async {
    final room = client.getRoomById(roomId);
    if (room == null) {
      return const RoomSearchResponse(isEncryptedRoom: true);
    }

    final offset = nextBatch == null ? 0 : (int.tryParse(nextBatch) ?? 0);
    final highlights = _splitHighlights(query);

    final hits = await database.search(
      query: query,
      roomId: roomId,
      limit: limit,
      offset: offset,
    );
    final total = await database.count(roomId: roomId, query: query);

    if (hits.isEmpty) {
      return RoomSearchResponse(
        count: total,
        highlights: highlights,
        isEncryptedRoom: true,
      );
    }

    final allEvents = await client.database.getEventList(room);
    const resolver = MessageDisplayResolver();
    final results = <RoomSearchResult>[];

    for (final hit in hits) {
      final message = _toDisplayMessage(hit, room);
      final context = _resolveContext(
        allEvents: allEvents,
        targetEventId: hit.eventId,
        targetTimestamp: hit.originServerTs,
        room: room,
        resolver: resolver,
      );
      results.add(RoomSearchResult(
        message: message,
        contextBefore: context.before,
        contextAfter: context.after,
      ));
    }

    final hasMore = hits.length == limit && total > offset + hits.length;

    return RoomSearchResponse(
      results: results,
      count: total,
      highlights: highlights,
      isEncryptedRoom: true,
      nextBatch: hasMore ? (offset + hits.length).toString() : null,
    );
  }

  static List<String> _splitHighlights(String query) {
    return query
        .trim()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
  }

  static KoheraMessageDisplay _toDisplayMessage(
    IndexedMessage hit,
    Room room,
  ) {
    final sender = room.unsafeGetUserFromMemoryOrFallback(hit.senderId);
    final body = stripReplyFallback(hit.body);

    return KoheraMessageDisplay(
      eventId: hit.eventId,
      senderId: hit.senderId,
      senderName: sender.calcDisplayname(),
      senderAvatarUrl: sender.avatarUrl?.toString(),
      body: body,
      messageType: hit.msgtype,
      eventType: EventTypes.Message,
      timestamp: hit.originServerTs,
      status: KoheraMessageStatus.sent,
      content: {'msgtype': hit.msgtype, 'body': body},
    );
  }

  static _MessageContext _resolveContext({
    required List<Event> allEvents,
    required String targetEventId,
    required DateTime targetTimestamp,
    required Room room,
    required MessageDisplayResolver resolver,
  }) {
    var index = allEvents.indexWhere((event) => event.eventId == targetEventId);

    if (index == -1) {
      index = _closestIndexByTimestamp(allEvents, targetTimestamp);
    }

    if (index == -1) {
      return const _MessageContext();
    }

    final beforeStart = index + 1;
    final beforeEnd = math.min(
      allEvents.length,
      beforeStart + contextBeforeLimit,
    );
    final before = beforeStart < allEvents.length
        ? allEvents
            .sublist(beforeStart, beforeEnd)
            .map((event) => resolver(event))
            .toList(growable: false)
        : const <KoheraMessageDisplay>[];

    final afterStart = math.max(0, index - contextAfterLimit);
    final after = afterStart < index
        ? allEvents
            .sublist(afterStart, index)
            .reversed
            .map((event) => resolver(event))
            .toList(growable: false)
        : const <KoheraMessageDisplay>[];

    return _MessageContext(before: before, after: after);
  }

  static int _closestIndexByTimestamp(List<Event> events, DateTime target) {
    if (events.isEmpty) return -1;

    var bestIndex = 0;
    var bestDiff = events[0].originServerTs.difference(target).abs();

    for (var i = 1; i < events.length; i++) {
      final diff = events[i].originServerTs.difference(target).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestIndex = i;
      }
    }

    return bestIndex;
  }
}

class _MessageContext {
  const _MessageContext({
    this.before = const [],
    this.after = const [],
  });

  final List<KoheraMessageDisplay> before;
  final List<KoheraMessageDisplay> after;
}
