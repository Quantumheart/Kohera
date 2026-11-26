import 'package:flutter/foundation.dart';

/// SDK-free view of a thread: its root event plus reply metadata.
///
/// Produced by `MessageRepository.fetchThreadSummaries` (server path).
/// Conversion from SDK types happens in the data layer; widgets read only
/// these fields.
@immutable
class KoheraThreadSummary {
  const KoheraThreadSummary({
    required this.rootEventId,
    required this.rootBody,
    required this.rootRedacted,
    required this.rootTimestamp,
    required this.replyCount,
    required this.unreadCount,
    required this.lastActivity,
    this.lastReplySenderName,
    this.lastReplyBody,
    this.lastReplyRedacted = false,
  });

  /// The thread root's event ID.
  final String rootEventId;

  /// The root event's display body (decrypted when applicable).
  final String rootBody;

  /// Whether the root event has been redacted.
  final bool rootRedacted;

  /// The root event's server timestamp.
  final DateTime rootTimestamp;

  /// The number of thread replies.
  final int replyCount;

  /// Replies from other users newer than the user's thread read receipt.
  final int unreadCount;

  /// The most recent activity timestamp (last reply, else the root).
  final DateTime lastActivity;

  /// The last reply's sender display name, or null when there are no
  /// replies.
  final String? lastReplySenderName;

  /// The last reply's display body, or null when there are no replies.
  final String? lastReplyBody;

  /// Whether the last reply has been redacted.
  final bool lastReplyRedacted;
}
