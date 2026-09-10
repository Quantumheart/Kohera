import 'package:kohera/data/models/kohera_room_summary.dart';
import 'package:kohera/data/utils/event_preview.dart';
import 'package:matrix/matrix.dart';

/// Converts a Matrix SDK [Room] into a [KoheraRoomSummary] domain model.
///
/// This is the conversion boundary for `Room` → `KoheraRoomSummary`.
/// It pre-computes the display name, last event preview, typing display
/// names, and other display fields once, rather than on every widget build.
///
/// Called by the sync-driven builder in `SelectionService` (cached per sync
/// cycle) as `const RoomSummaryResolver()(room, myUserId: id)`.
class RoomSummaryResolver {
  const RoomSummaryResolver();

  KoheraRoomSummary call(Room room, {String? myUserId}) {
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
      spaceChildCount: room.isSpace ? room.spaceChildren.length : 0,
      isFavourite: room.isFavourite,
    );
  }

  String _lastEventPreview(Event? event, Room room, String? myUserId) =>
      event == null
          ? EventPreviewText.noMessages
          : eventPreviewText(event, room: room, myUserId: myUserId);
}
