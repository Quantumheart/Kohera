import 'package:flutter/foundation.dart';

import 'package:kohera/data/models/kohera_message_display.dart';

/// A single search hit returned by [RoomSearchService].
///
/// Wraps the matched message ([message]) together with the surrounding
/// context events ([contextBefore] / [contextAfter]) and the server-assigned
/// relevance [rank], if any. Produced exclusively by
/// `RoomSearchService` from a Matrix `v3/search` response; display widgets
/// consume this model without touching the Matrix SDK.
@immutable
class RoomSearchResult {
  const RoomSearchResult({
    required this.message,
    this.contextBefore = const [],
    this.contextAfter = const [],
    this.rank,
  });

  /// The matched message, pre-computed for display.
  final KoheraMessageDisplay message;

  /// Events immediately before the match, oldest-first, as returned by the
  /// server's `event_context`. Empty when no context was requested/returned.
  final List<KoheraMessageDisplay> contextBefore;

  /// Events immediately after the match, oldest-first, as returned by the
  /// server's `event_context`. Empty when no context was requested/returned.
  final List<KoheraMessageDisplay> contextAfter;

  /// A server-assigned relevance score. Higher is closer to the query.
  /// `null` when the server did not return a rank (e.g. `recent` ordering).
  final double? rank;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomSearchResult && message == other.message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() =>
      'RoomSearchResult(eventId: ${message.eventId}, rank: $rank, '
      'contextBefore: ${contextBefore.length}, '
      'contextAfter: ${contextAfter.length})';
}

/// The full response of a single [RoomSearchService] search call for one room.
@immutable
class RoomSearchResponse {
  const RoomSearchResponse({
    this.results = const [],
    this.nextBatch,
    this.count,
    this.highlights,
    this.isEncryptedRoom = false,
    this.hasLocalIndex = false,
  });

  /// Search hits for this page, ordered as the server returned them.
  final List<RoomSearchResult> results;

  /// Pagination token for the next page, or `null` when there are no more.
  final String? nextBatch;

  /// The server's approximate total match count, or `null` when absent.
  final int? count;

  /// Terms the server suggests highlighting, or `null` when absent.
  final List<String>? highlights;

  /// `true` when the room is encrypted and the server search was skipped
  /// in favour of the local FTS5 index (see `LocalSearchService`).
  final bool isEncryptedRoom;

  /// `true` when a local search index was available and used for this
  /// response. `false` for unencrypted (server-side) searches and for
  /// encrypted searches on platforms without FTS5 support (e.g. web). The
  /// UI uses this to distinguish "no results" from "search not available
  /// on this platform".
  final bool hasLocalIndex;

  @override
  String toString() =>
      'RoomSearchResponse(results: ${results.length}, count: $count, '
      'nextBatch: $nextBatch, isEncryptedRoom: $isEncryptedRoom)';
}
