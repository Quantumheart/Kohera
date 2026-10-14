import 'package:flutter/foundation.dart';

/// A single message match from global (cross-room) search.
///
/// Produced by [MessageSearchRepository] from either a server-side
/// `v3/search` response, the local FTS5 index, or the timeline-scan
/// fallback. SDK-free — consumed by the room list UI without touching
/// `package:matrix`.
@immutable
class MessageSearchResult {
  const MessageSearchResult({
    required this.roomId,
    required this.roomName,
    required this.senderName,
    required this.senderId,
    required this.body,
    required this.eventId,
    required this.originServerTs,
  });

  final String roomId;
  final String roomName;
  final String senderName;
  final String senderId;
  final String body;
  final String eventId;
  final DateTime originServerTs;
}
