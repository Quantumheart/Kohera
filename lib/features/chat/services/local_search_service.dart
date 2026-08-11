import 'package:flutter/foundation.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/models/kohera_message_status.dart';
import 'package:kohera/features/chat/models/room_search_result.dart';
import 'package:kohera/features/chat/services/message_display_resolver.dart';
import 'package:kohera/features/chat/services/message_search_database.dart';
import 'package:matrix/matrix.dart';

/// Searches encrypted rooms using the local FTS5 index
/// ([MessageSearchDatabase]).
///
/// The Matrix homeserver cannot search encrypted room content — it has no
/// access to the decryption keys. This service queries the on-device FTS5
/// index built by `MessageIndexerService`, retrieves ±3 events of context
/// for each hit from the room's local event store, and packages the result as
/// a [RoomSearchResponse] flagged `isEncryptedRoom: true` so it flows through
/// the same UI as server-side search.
///
/// **Matched message**: resolved from the full local [Event] via
/// `getEventById` (so it works for matches of any age) and decrypted before
/// display; falls back to a display built from the indexed fields when the
/// event is no longer in the local store.
///
/// **Context**: the room's local event list is scanned in bounded chunks
/// (newest-first) collecting the ±3 events closest in timestamp to each hit,
/// stopping early once every hit has its surrounding context. Only the
/// selected context events are decrypted. This bounds memory regardless of
/// room size while preserving context for older matches.
///
/// Pagination is offset-based: the next page offset is encoded into
/// [RoomSearchResponse.nextBatch] as a decimal string.
class LocalSearchService {
  LocalSearchService({
    required this.client,
    required this.database,
    this.getTimeline,
  });

  final Client client;
  final MessageSearchDatabase database;

  /// Optional accessor for the room's live [Timeline], used to aggregate edits
  /// (and reply/thread relations) when resolving matched messages and their
  /// context. `null` when no timeline is available (e.g. before the room has
  /// loaded); resolution then falls back to the indexed (already-edited) body.
  final Timeline? Function()? getTimeline;

  /// Number of context events to retrieve before and after each match.
  static const contextBeforeLimit = 3;
  static const contextAfterLimit = 3;

  /// Page size for the chunked local event-list scan used for context
  /// retrieval. Bounds the number of [Event]s held in memory at once.
  static const _chunkSize = 500;

  /// Searches [roomId] for [query] against the local FTS5 index.
  ///
  /// [nextBatch] carries the offset for pagination (a decimal string produced
  /// by a previous call). [limit] caps the number of matches returned in a
  /// single page.
  Future<RoomSearchResponse> search({
    required String roomId,
    required String query,
    String? nextBatch,
    int limit = 50,
  }) async {
    if (!database.isAvailable) {
      // Platform without FTS5 (web): signal "not available" via an empty
      // encrypted-room response. The UI distinguishes this from "no results"
      // using whether a local index is available.
      return const RoomSearchResponse(isEncryptedRoom: true);
    }

    final offset = _parseOffset(nextBatch);

    final matches = await database.search(
      roomId: roomId,
      query: query,
      limit: limit,
      offset: offset,
    );
    final count = await database.count(roomId: roomId, query: query);

    final room = client.getRoomById(roomId);
    // The room's live timeline (if loaded) drives edit/reply aggregation via
    // `Event.getDisplayEvent`. May be null early in the room lifecycle; the
    // indexed (already-edited) body is used as a fallback then.
    final timeline = getTimeline?.call();
    const resolver = MessageDisplayResolver();
    final results = <RoomSearchResult>[];

    if (matches.isEmpty || room == null) {
      // No hits, or the room isn't in the client (e.g. left but still
      // indexed): show what the index has, without context.
      for (final match in matches) {
        results.add(
          RoomSearchResult(message: _displayFromIndex(match, room: room)),
        );
      }
    } else {
      final beforeByMatch = <IndexedMessage, List<Event>>{};
      final afterByMatch = <IndexedMessage, List<Event>>{};
      await _collectContext(
        room: room,
        matches: matches,
        beforeByMatch: beforeByMatch,
        afterByMatch: afterByMatch,
      );

      for (final match in matches) {
        final message =
            await _resolveMatchedMessage(room, match, resolver, timeline);
        final before = await _resolveContextList(
          beforeByMatch[match] ?? const [],
          resolver,
          timeline,
        );
        final after = await _resolveContextList(
          afterByMatch[match] ?? const [],
          resolver,
          timeline,
        );
        results.add(RoomSearchResult(
          message: message,
          contextBefore: before,
          contextAfter: after,
        ));
      }
    }

    // Encode the next offset only when this page was full (there may be more).
    final nextOffset =
        matches.length < limit ? null : (offset + matches.length).toString();

    return RoomSearchResponse(
      results: results,
      nextBatch: nextOffset,
      count: count,
      highlights: _highlightTerms(query),
      isEncryptedRoom: true,
      hasLocalIndex: true,
    );
  }

  /// Parses a [nextBatch] pagination token into a row offset.
  /// `null` or an unparseable token starts from the beginning.
  static int _parseOffset(String? nextBatch) {
    if (nextBatch == null || nextBatch.isEmpty) return 0;
    return int.tryParse(nextBatch) ?? 0;
  }

  /// Splits [query] into whitespace-separated terms for client-side
  /// highlighting (the local index provides no highlight terms of its own).
  static List<String> _highlightTerms(String query) {
    final terms = query
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    return terms.isEmpty ? const [] : terms;
  }

  /// Scans the room's local event list in bounded, newest-first chunks and
  /// collects the [contextBeforeLimit]/[contextAfterLimit] events closest in
  /// timestamp to each hit into [beforeByMatch]/[afterByMatch].
  ///
  /// Stops early once every hit has passed its position and gathered enough
  /// older context, so recent hits don't force a full scan. Memory is bounded
  /// to one chunk at a time (plus the ±3 slices per hit).
  Future<void> _collectContext({
    required Room room,
    required List<IndexedMessage> matches,
    required Map<IndexedMessage, List<Event>> beforeByMatch,
    required Map<IndexedMessage, List<Event>> afterByMatch,
  }) async {
    // `true` once the scan has moved past a hit (seen an older event), meaning
    // its "after" (newer) context is finalized.
    final passed = {for (final m in matches) m: false};
    final done = <IndexedMessage>{};
    var start = 0;

    while (done.length < matches.length) {
      final chunk = await _loadEventChunk(room, start);
      if (chunk.isEmpty) break;

      for (final event in chunk) {
        for (final m in matches) {
          if (done.contains(m)) continue;

          final cmp = event.originServerTs.compareTo(m.originServerTs);
          // Skip the hit itself and any event sharing its exact timestamp.
          if (cmp == 0) continue;

          if (cmp < 0) {
            // Older than the hit: a "before" candidate. The scan is newest-
            // first, so the first older events seen are the closest (most
            // recent) older ones — keep only the first few.
            passed[m] = true;
            final list = beforeByMatch.putIfAbsent(m, () => <Event>[]);
            if (list.length < contextBeforeLimit) list.add(event);
          } else {
            // Newer than the hit: an "after" candidate, newest-first. Keep the
            // last few seen (closest to the hit from above).
            final list = afterByMatch.putIfAbsent(m, () => <Event>[]);
            list.add(event);
            if (list.length > contextAfterLimit) list.removeAt(0);
          }

          // A hit is complete once we've moved past it and gathered enough
          // older context. ("after" is finalized once passed.)
          if (passed[m]! &&
              (beforeByMatch[m]?.length ?? 0) >= contextBeforeLimit) {
            done.add(m);
          }
        }
      }

      if (chunk.length < _chunkSize) break; // end of the local event list
      start += _chunkSize;
    }
  }

  /// Loads one bounded page of the room's local event list.
  /// Returns an empty list when the fetch fails.
  Future<List<Event>> _loadEventChunk(Room room, int start) async {
    try {
      return await client.database.getEventList(
        room,
        start: start,
        limit: _chunkSize,
      );
    } catch (e) {
      debugPrint('[Kohera] Local search: getEventList failed for ${room.id}: $e');
      return const [];
    }
  }

  /// Resolves a hit's matched message from the full local [Event],
  /// decrypting it first for encrypted rooms and applying edit aggregation
  /// via [timeline] (`Event.getDisplayEvent`) when the timeline has loaded
  /// the relevant edit.
  ///
  /// The FTS index already stores the edited body (under the original event
  /// id), so when the timeline hasn't aggregated an edit for this hit (e.g.
  /// an old message whose edit is also old and no longer in the loaded
  /// timeline) the indexed body is preferred over the stored event's
  /// pre-edit body. Falls back to the indexed fields entirely when the event
  /// is missing or undecryptable.
  Future<KoheraMessageDisplay> _resolveMatchedMessage(
    Room room,
    IndexedMessage match,
    MessageDisplayResolver resolver,
    Timeline? timeline,
  ) async {
    Event? event;
    try {
      event = await client.database.getEventById(match.eventId, room);
    } catch (e) {
      debugPrint('[Kohera] Local search: resolve match ${match.eventId}: $e');
    }
    if (event == null) {
      return _displayFromIndex(match, room: room);
    }

    final decrypted = await _decryptIfNeeded(event);

    // Edit aggregated in the loaded timeline → resolve with the timeline so
    // getDisplayEvent applies the latest edit (body, formatted text, …).
    if (timeline != null &&
        decrypted.hasAggregatedEvents(timeline, RelationshipTypes.edit)) {
      return resolver(decrypted, timeline: timeline);
    }

    // No aggregated edit. If the indexed body differs from the stored event
    // body the message was edited but the edit isn't in the loaded timeline —
    // prefer the (already-edited) indexed body over the pre-edit one.
    if (decrypted.body != match.body) {
      return _displayFromIndex(match, room: room);
    }

    // Not edited (or edit already matches): rich display via the resolver,
    // using the timeline for reply stripping / relations when available.
    return resolver(decrypted, timeline: timeline);
  }

  /// Decrypts and converts a list of context events to display models,
  /// ordered oldest-first to match the server-side `event_context` contract.
  /// Passes [timeline] to the resolver so edits on context events are
  /// aggregated when the timeline has them loaded.
  Future<List<KoheraMessageDisplay>> _resolveContextList(
    List<Event> events,
    MessageDisplayResolver resolver,
    Timeline? timeline,
  ) async {
    if (events.isEmpty) return const [];
    final sorted = List<Event>.from(events)
      ..sort((a, b) => a.originServerTs.compareTo(b.originServerTs));
    final out = <KoheraMessageDisplay>[];
    for (final event in sorted) {
      out.add(resolver(await _decryptIfNeeded(event), timeline: timeline));
    }
    return out;
  }

  /// Decrypts an [Event] if it is encrypted, returning the original event
  /// unchanged when decryption isn't needed or isn't possible (no encryption
  /// handler, timeout, or missing key). Mirrors `MessageIndexerService`'s
  /// graceful-decryption behaviour.
  Future<Event> _decryptIfNeeded(Event event) async {
    if (event.type != EventTypes.Encrypted) return event;
    final encryption = client.encryption;
    if (encryption == null) return event;
    try {
      return await encryption
          .decryptRoomEvent(event)
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      return event;
    }
  }

  /// Builds a [KoheraMessageDisplay] directly from an [IndexedMessage],
  /// resolving the sender's display name / avatar from the room's member
  /// cache. Used when the full [Event] is no longer in the local store.
  KoheraMessageDisplay _displayFromIndex(IndexedMessage msg, {Room? room}) {
    var senderName = msg.senderId;
    String? senderAvatarUrl;
    if (room != null) {
      try {
        final user = room.unsafeGetUserFromMemoryOrFallback(msg.senderId);
        senderName = user.calcDisplayname();
        senderAvatarUrl = user.avatarUrl?.toString();
      } catch (_) {
        // Keep the raw sender id as the display name fallback.
      }
    }

    return KoheraMessageDisplay(
      eventId: msg.eventId,
      senderId: msg.senderId,
      senderName: senderName,
      senderAvatarUrl: senderAvatarUrl,
      body: msg.body,
      messageType: msg.msgtype,
      eventType: EventTypes.Message,
      timestamp: msg.originServerTs,
      status: KoheraMessageStatus.sent,
      content: const {},
    );
  }
}
