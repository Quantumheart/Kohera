import 'package:kohera/features/rooms/services/room_list_search_controller.dart';
import 'package:kohera/features/spaces/models/space_rooms_model.dart';
import 'package:kohera/shared/models/kohera_room_summary.dart';

// ── List item types for the flat interleaved list ──────────
sealed class ListItem {}

class HeaderItem extends ListItem {
  final String name;
  final String sectionKey;
  final int depth;
  final int roomCount;
  final bool isSpace;

  HeaderItem({
    required this.name,
    required this.sectionKey,
    required this.depth,
    required this.roomCount,
    this.isSpace = false,
  });
}

class RoomItem extends ListItem {
  final KoheraRoomSummary summary;
  final int depth;
  final String? parentSpaceId;
  final List<String>? sectionRoomIds;

  RoomItem({
    required this.summary,
    this.depth = 0,
    this.parentSpaceId,
    List<String>? sectionRoomIds,
  }) : sectionRoomIds =
            sectionRoomIds != null ? List.unmodifiable(sectionRoomIds) : null;
}

class InviteItem extends ListItem {
  final KoheraRoomSummary summary;
  InviteItem({required this.summary});
}

class MessageSearchHeaderItem extends ListItem {
  final int? resultCount;
  final bool isLoading;
  final String? error;

  MessageSearchHeaderItem({
    required this.isLoading,
    this.resultCount,
    this.error,
  });
}

class MessageSearchResultItem extends ListItem {
  final MessageSearchResult result;
  MessageSearchResultItem({required this.result});
}

class LoadMoreMessagesItem extends ListItem {
  final bool isLoading;
  LoadMoreMessagesItem({required this.isLoading});
}

// ── Unjoined room group (inline in space sections) ──────────

class UnjoinedRoomGroupHeaderItem extends ListItem {
  final String spaceId;
  final int unjoinedCount;

  UnjoinedRoomGroupHeaderItem({
    required this.spaceId,
    required this.unjoinedCount,
  });
}

class UnjoinedRoomItem extends ListItem {
  final SpaceRoomMetadata metadata;
  final String parentSpaceId;
  final int depth;

  UnjoinedRoomItem({
    required this.metadata,
    required this.parentSpaceId,
    this.depth = 0,
  });
}

class SubspaceOpenItem extends ListItem {
  final SpaceRoomMetadata metadata;
  final String parentSpaceId;
  final int depth;

  SubspaceOpenItem({
    required this.metadata,
    required this.parentSpaceId,
    this.depth = 0,
  });
}

class UnjoinedRoomLoadingItem extends ListItem {
  final int depth;
  UnjoinedRoomLoadingItem({this.depth = 0});
}

class UnjoinedRoomErrorItem extends ListItem {
  final String error;
  final String spaceId;
  final int depth;

  UnjoinedRoomErrorItem({
    required this.error,
    required this.spaceId,
    this.depth = 0,
  });
}

class UnjoinedRoomForbiddenItem extends ListItem {
  final int depth;
  UnjoinedRoomForbiddenItem({this.depth = 0});
}
