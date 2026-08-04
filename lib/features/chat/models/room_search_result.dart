import 'package:flutter/foundation.dart';

import 'package:kohera/features/chat/models/kohera_message_display.dart';

@immutable
class RoomSearchResult {
  const RoomSearchResult({
    required this.message,
    required this.contextBefore,
    required this.contextAfter,
    required this.isEncryptedRoom,
    this.rank,
  });

  final KoheraMessageDisplay message;
  final List<KoheraMessageDisplay> contextBefore;
  final List<KoheraMessageDisplay> contextAfter;
  final bool isEncryptedRoom;
  final double? rank;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomSearchResult &&
          message.eventId == other.message.eventId;

  @override
  int get hashCode => message.eventId.hashCode;

  @override
  String toString() =>
      'RoomSearchResult(eventId: ${message.eventId}, '
      'contextBefore: ${contextBefore.length}, '
      'contextAfter: ${contextAfter.length}, '
      'rank: $rank, isEncryptedRoom: $isEncryptedRoom)';
}

@immutable
class RoomSearchResponse {
  const RoomSearchResponse({
    required this.results,
    required this.isEncryptedRoom,
    this.nextBatch,
    this.count,
    this.highlights,
  });

  final List<RoomSearchResult> results;
  final bool isEncryptedRoom;
  final String? nextBatch;
  final int? count;
  final List<String>? highlights;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomSearchResponse &&
          results.length == other.results.length &&
          nextBatch == other.nextBatch &&
          count == other.count;

  @override
  int get hashCode => Object.hash(results, nextBatch, count);

  @override
  String toString() =>
      'RoomSearchResponse(results: ${results.length}, '
      'nextBatch: $nextBatch, count: $count, '
      'highlights: $highlights, isEncryptedRoom: $isEncryptedRoom)';
}
