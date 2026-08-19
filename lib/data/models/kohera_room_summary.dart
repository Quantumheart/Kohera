import 'package:flutter/foundation.dart';

/// A Kohera-owned domain model representing a Matrix room with pre-computed
/// display fields.
///
/// This is the primary room model for room list tiles, chat app bar, typing
/// indicator, space rail, and shared room widgets. It carries no
/// `package:matrix/matrix.dart` dependency — the SDK `Room` is converted to
/// this type at the sync-driven conversion boundary in `SelectionService`.
///
/// The summary is an immutable snapshot recomputed on each sync cycle.
/// `KoheraRoomPermissions` (slice #9) will add permission fields,
/// `KoheraRoomMemberList` (slice #10) will add member fields.
@immutable
class KoheraRoomSummary {
  const KoheraRoomSummary({
    required this.roomId,
    required this.displayname,
    required this.isDirectChat,
    required this.isEncrypted,
    required this.isSpace,
    required this.notificationCount,
    required this.highlightCount,
    required this.typingDisplayNames,
    required this.pinnedEventIds,
    required this.spaceChildCount,
    required this.isFavourite,
    required this.lastEventPreview,
    required this.lastEventIsThreadReply,
    this.avatarUrl,
    this.topic,
    this.canonicalAlias,
    this.dmUserId,
    this.lastEventBody,
    this.lastEventTimestamp,
    this.lastEventSenderName,
  });

  /// The Matrix room ID (e.g. `!abc:example.com`).
  final String roomId;

  /// The resolved display name via `Room.getLocalizedDisplayname()`.
  final String displayname;

  /// The raw `mxc://` avatar URI as a string, or `null`.
  final String? avatarUrl;

  /// The room topic / description, or `null`.
  final String? topic;

  /// The canonical alias (e.g. `#room:example.com`), or empty/null.
  final String? canonicalAlias;

  /// Whether this is a direct (1:1) chat.
  final bool isDirectChat;

  /// The DM partner's Matrix user ID, if this is a direct chat.
  final String? dmUserId;

  /// Whether the room is end-to-end encrypted.
  final bool isEncrypted;

  /// Fully formatted last event preview text (e.g. '📷 Image', 'Call in
  /// progress', 'Hello world'). Pre-computed at the conversion boundary.
  final String lastEventPreview;

  /// Raw body of the last event, for notification keyword matching.
  final String? lastEventBody;

  /// Timestamp of the last event, or `null` if the room has no events.
  final DateTime? lastEventTimestamp;

  /// Display name of the last event sender, or `null`.
  final String? lastEventSenderName;

  /// Whether the last event is a thread reply.
  final bool lastEventIsThreadReply;

  /// Raw notification count from the SDK (before preference filtering).
  final int notificationCount;

  /// Raw highlight (mention) count from the SDK.
  final int highlightCount;

  /// Pre-resolved display names of users currently typing (excluding self).
  final List<String> typingDisplayNames;

  /// List of pinned event IDs.
  final List<String> pinnedEventIds;

  /// Whether this room is a space.
  final bool isSpace;

  /// Number of space children (for spaces).
  final int spaceChildCount;

  /// Whether this room is marked as a favourite (for pinning).
  final bool isFavourite;

  KoheraRoomSummary copyWith({
    String? roomId,
    String? displayname,
    String? avatarUrl,
    String? topic,
    String? canonicalAlias,
    bool? isDirectChat,
    String? dmUserId,
    bool? isEncrypted,
    String? lastEventPreview,
    String? lastEventBody,
    DateTime? lastEventTimestamp,
    String? lastEventSenderName,
    bool? lastEventIsThreadReply,
    int? notificationCount,
    int? highlightCount,
    List<String>? typingDisplayNames,
    List<String>? pinnedEventIds,
    bool? isSpace,
    int? spaceChildCount,
    bool? isFavourite,
  }) =>
      KoheraRoomSummary(
        roomId: roomId ?? this.roomId,
        displayname: displayname ?? this.displayname,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        topic: topic ?? this.topic,
        canonicalAlias: canonicalAlias ?? this.canonicalAlias,
        isDirectChat: isDirectChat ?? this.isDirectChat,
        dmUserId: dmUserId ?? this.dmUserId,
        isEncrypted: isEncrypted ?? this.isEncrypted,
        lastEventPreview: lastEventPreview ?? this.lastEventPreview,
        lastEventBody: lastEventBody ?? this.lastEventBody,
        lastEventTimestamp: lastEventTimestamp ?? this.lastEventTimestamp,
        lastEventSenderName: lastEventSenderName ?? this.lastEventSenderName,
        lastEventIsThreadReply:
            lastEventIsThreadReply ?? this.lastEventIsThreadReply,
        notificationCount: notificationCount ?? this.notificationCount,
        highlightCount: highlightCount ?? this.highlightCount,
        typingDisplayNames: typingDisplayNames ?? this.typingDisplayNames,
        pinnedEventIds: pinnedEventIds ?? this.pinnedEventIds,
        isSpace: isSpace ?? this.isSpace,
        spaceChildCount: spaceChildCount ?? this.spaceChildCount,
        isFavourite: isFavourite ?? this.isFavourite,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KoheraRoomSummary && roomId == other.roomId;

  @override
  int get hashCode => roomId.hashCode;

  @override
  String toString() => 'KoheraRoomSummary(roomId: $roomId, '
      'displayname: $displayname, isSpace: $isSpace)';
}
