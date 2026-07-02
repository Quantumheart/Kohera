import 'package:kohera/core/utils/reply_fallback.dart';
import 'package:kohera/features/calling/models/call_constants.dart';
import 'package:kohera/features/rooms/models/kohera_room_summary.dart';
import 'package:matrix/matrix.dart';

/// Converts a Matrix SDK [Room] into a [KoheraRoomSummary] domain model.
///
/// This is the conversion boundary for `Room` → `KoheraRoomSummary`.
/// It pre-computes the display name, last event preview, typing display
/// names, and other display fields once, rather than on every widget build.
///
/// Called by the sync-driven builder in `SelectionService` (cached per
/// sync cycle).
KoheraRoomSummary toKoheraRoomSummary(Room room, {String? myUserId}) {
  final lastEvent = room.lastEvent;
  final typingNames = room.typingUsers
      .where((u) => u.id != myUserId)
      .map((u) => u.displayName ?? u.id)
      .toList();

  return KoheraRoomSummary(
    roomId: room.id,
    displayname: room.getLocalizedDisplayname(),
    avatarUrl: room.avatar?.toString(),
    topic: room.topic,
    canonicalAlias: room.canonicalAlias.isNotEmpty ? room.canonicalAlias : null,
    isDirectChat: room.isDirectChat,
    dmUserId: room.isDirectChat ? room.directChatMatrixID : null,
    isEncrypted: room.encrypted,
    lastEventPreview: _lastEventPreview(lastEvent, room, myUserId),
    lastEventBody: lastEvent?.body,
    lastEventTimestamp: lastEvent?.originServerTs,
    lastEventSenderName: lastEvent?.senderFromMemoryOrFallback.calcDisplayname(),
    lastEventIsThreadReply:
        lastEvent?.relationshipType == RelationshipTypes.thread,
    notificationCount: room.notificationCount,
    highlightCount: room.highlightCount,
    typingDisplayNames: typingNames,
    pinnedEventIds: room.pinnedEventIds.toList(),
    isSpace: room.isSpace,
    spaceChildCount: room.spaceChildren.length,
    isFavourite: room.isFavourite,
  );
}

/// Replicates the last-event preview logic from RoomTile._lastMessagePreview.
String _lastEventPreview(Event? event, Room room, String? myUserId) {
  if (event == null) return 'No messages yet';
  if (event.type == kCallInvite) return 'Call in progress';
  if (event.type == kCallMember ||
      event.type == kCallMemberMsc ||
      event.body.contains(kCallMember) ||
      event.body.contains(kCallMemberMsc)) {
    return event.senderId == myUserId ? 'You initiated a call' : 'Call';
  }
  if (event.type == kCallHangup) {
    final reason = event.content.tryGet<String>('reason');
    if (reason == 'invite_timeout') return 'Missed call';
    return 'Call ended';
  }
  if (event.redacted) {
    final isMe = event.senderId == myUserId;
    if (isMe) return 'You deleted this message';
    final redactor = event.redactedBecause?.senderId;
    final isSelfRedact = redactor == event.senderId;
    if (isSelfRedact || redactor == null) return 'This message was deleted';
    final redactorUser =
        room.unsafeGetUserFromMemoryOrFallback(redactor);
    return 'Deleted by ${redactorUser.displayName ?? redactor}';
  }
  if (event.messageType == MessageTypes.BadEncrypted) {
    return '🔒 Unable to decrypt';
  }
  final body = stripReplyFallback(event.body);
  if (event.messageType == MessageTypes.Text) {
    return body;
  }
  if (event.messageType == MessageTypes.Image) return '📷 Image';
  if (event.messageType == MessageTypes.Video) return '🎬 Video';
  if (event.messageType == MessageTypes.File) return '📎 File';
  if (event.messageType == MessageTypes.Audio) return '🎵 Audio';
  return body;
}
