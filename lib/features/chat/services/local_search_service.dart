import 'package:flutter/foundation.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/models/kohera_message_status.dart';
import 'package:kohera/features/chat/models/room_search_result.dart';
import 'package:kohera/features/chat/services/message_display_resolver.dart';
import 'package:kohera/features/chat/services/message_search_database.dart';
import 'package:matrix/matrix.dart';

class LocalSearchService {
  LocalSearchService({required this.client, required this.database});

  final Client client;
  final MessageSearchDatabase database;

  Future<RoomSearchResponse> search({
    required String roomId,
    required String query,
    String? nextBatch,
    int limit = 50,
  }) async {
    final offset = nextBatch != null ? int.tryParse(nextBatch) ?? 0 : 0;

    final results = await database.search(
      roomId: roomId,
      query: query,
      limit: limit,
      offset: offset,
    );
    final count = await database.count(roomId: roomId, query: query);

    final room = client.getRoomById(roomId);
    const resolver = MessageDisplayResolver();

    final searchResults = <RoomSearchResult>[];
    for (final msg in results) {
      final context = room != null
          ? await _getContext(room, msg, resolver)
          : (const <KoheraMessageDisplay>[], const <KoheraMessageDisplay> []);

      searchResults.add(RoomSearchResult(
        message: _toDisplay(msg, room),
        contextBefore: context.$1,
        contextAfter: context.$2,
        isEncryptedRoom: true,
      ));
    }

    return RoomSearchResponse(
      results: searchResults,
      isEncryptedRoom: true,
      nextBatch: results.length < limit ? null : (offset + limit).toString(),
      count: count,
      highlights: _extractHighlightTerms(query),
    );
  }

  Future<(List<KoheraMessageDisplay>, List<KoheraMessageDisplay>)> _getContext(
    Room room,
    IndexedMessage msg,
    MessageDisplayResolver resolver,
  ) async {
    try {
      final db = client.database;
      final events = await db.getEventList(room, limit: 200);
      final sorted = events.toList()
        ..sort((a, b) => a.originServerTs.compareTo(b.originServerTs));

      final matchIndex = sorted.indexWhere((e) => e.eventId == msg.eventId);
      if (matchIndex == -1) {
        return (const <KoheraMessageDisplay>[], const <KoheraMessageDisplay> []);
      }

      final before = <KoheraMessageDisplay>[];
      final after = <KoheraMessageDisplay>[];
      const contextSize = 3;

      for (var i = matchIndex - 1;
          i >= 0 && before.length < contextSize;
          i--) {
        if (sorted[i].type == EventTypes.Message && !sorted[i].redacted) {
          before.insert(0, resolver(sorted[i]));
        }
      }
      for (var i = matchIndex + 1;
          i < sorted.length && after.length < contextSize;
          i++) {
        if (sorted[i].type == EventTypes.Message && !sorted[i].redacted) {
          after.add(resolver(sorted[i]));
        }
      }

      return (before, after);
    } catch (e) {
      debugPrint('[Kohera] Local search context retrieval error: $e');
      return (const <KoheraMessageDisplay>[], const <KoheraMessageDisplay> []);
    }
  }

  KoheraMessageDisplay _toDisplay(IndexedMessage msg, Room? room) {
    var senderName = msg.senderId;
    String? senderAvatarUrl;

    if (room != null) {
      try {
        final user = room.unsafeGetUserFromMemoryOrFallback(msg.senderId);
        senderName = user.calcDisplayname();
        senderAvatarUrl = user.avatarUrl?.toString();
      } catch (_) {}
    }

    return KoheraMessageDisplay(
      eventId: msg.eventId,
      senderId: msg.senderId,
      senderName: senderName,
      senderAvatarUrl: senderAvatarUrl,
      body: msg.body,
      messageType: msg.msgtype ?? 'm.text',
      eventType: 'm.room.message',
      timestamp: DateTime.fromMillisecondsSinceEpoch(msg.originServerTs),
      status: KoheraMessageStatus.sent,
      content: const {},
    );
  }

  List<String> _extractHighlightTerms(String query) {
    return query
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
  }
}
