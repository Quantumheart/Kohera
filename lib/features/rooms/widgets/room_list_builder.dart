import 'package:kohera/core/models/space_node.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/rooms/widgets/room_list_models.dart';
import 'package:kohera/features/spaces/models/space_rooms_model.dart';
import 'package:kohera/features/spaces/services/space_rooms_controller.dart';
import 'package:matrix/matrix.dart';

// ── Section-building helpers for the room list ──────────

bool roomMatchesQuery(Room r, String q) {
  if (r.getLocalizedDisplayname().toLowerCase().contains(q)) return true;

  final alias = r.canonicalAlias;
  if (alias.isNotEmpty && alias.toLowerCase().contains(q)) return true;

  final dmPartner = r.directChatMatrixID;
  if (dmPartner != null && dmPartner.toLowerCase().contains(q)) return true;

  return false;
}

List<Room> applySearch(List<Room> rooms, String query) {
  if (query.isEmpty) return rooms;
  final q = query.toLowerCase();
  return rooms.where((r) => roomMatchesQuery(r, q)).toList();
}

Set<String>? spaceRoomIds(SelectionService matrix) {
  final selectedIds = matrix.selectedSpaceIds;
  if (selectedIds.isEmpty) return null;

  final ids = <String>{};
  void collect(SpaceNode node) {
    ids.addAll(node.directChildRoomIds);
    for (final sub in node.subspaces) {
      collect(sub);
    }
  }
  for (final node in matrix.spaceTree) {
    if (selectedIds.contains(node.summary.roomId)) collect(node);
  }
  return ids;
}

List<ListItem> buildSectionItems(
  SelectionService matrix,
  PreferencesService prefs,
  String query, {
  SpaceRoomsController? spaceRoomsController,
}) {
  final collapsed = prefs.collapsedSpaceSections;
  final selectedIds = matrix.selectedSpaceIds;
  final tree = matrix.spaceTree;
  final items = <ListItem>[];

  // Invited rooms at the top (filtered by search)
  final invitedRooms = applySearch(matrix.invitedRooms, query);
  for (final room in invitedRooms) {
    items.add(InviteItem(summary: matrix.summaryFor(room)));
  }

  final pinnedIds = <String>{};

  if (selectedIds.isNotEmpty) {
    // Space selected: show only that space's rooms with subspace hierarchy
    final visibleNodes = tree
        .where((n) => selectedIds.contains(n.summary.roomId))
        .toList();
    for (final node in visibleNodes) {
      _addSpaceSection(items, node, 0, matrix, collapsed, pinnedIds, query,
          spaceRoomsController,);
    }
  } else {
    // No space selected (Home): Pinned → DMs → Unsorted

    // Pinned section
    final pinnedRooms = applySearch(
        matrix.rooms.where((r) => r.isFavourite).toList(), query,);
    pinnedIds.addAll(pinnedRooms.map((r) => r.id));
    if (pinnedRooms.isNotEmpty) {
      items.add(HeaderItem(
        name: 'Pinned',
        sectionKey: PreferencesService.pinnedSectionKey,
        depth: 0,
        roomCount: pinnedRooms.length,
      ),);
      if (!collapsed.contains(PreferencesService.pinnedSectionKey)) {
        for (final room in pinnedRooms) {
          items.add(RoomItem(summary: matrix.summaryFor(room)));
        }
      }
    }

    // DMs section — all direct chats
    final dmRooms = applySearch(
        matrix.rooms.where((r) => r.isDirectChat && !pinnedIds.contains(r.id)).toList(), query,);
    if (dmRooms.isNotEmpty) {
      items.add(HeaderItem(
        name: 'Direct Messages',
        sectionKey: PreferencesService.dmSectionKey,
        depth: 0,
        roomCount: dmRooms.length,
      ),);
      if (!collapsed.contains(PreferencesService.dmSectionKey)) {
        for (final room in dmRooms) {
          items.add(RoomItem(summary: matrix.summaryFor(room)));
        }
      }
    }

    // Unsorted section (orphan group rooms)
    final orphans = applySearch(matrix.orphanRooms, query)
        .where((r) => !pinnedIds.contains(r.id) && !r.isDirectChat)
        .toList();
    if (orphans.isNotEmpty) {
      items.add(HeaderItem(
        name: 'Rooms',
        sectionKey: PreferencesService.unsortedSectionKey,
        depth: 0,
        roomCount: orphans.length,
      ),);
      if (!collapsed.contains(PreferencesService.unsortedSectionKey)) {
        for (final room in orphans) {
          items.add(RoomItem(summary: matrix.summaryFor(room)));
        }
      }
    }
  }

  return items;
}

void _addSpaceSection(
  List<ListItem> items,
  SpaceNode node,
  int depth,
  SelectionService matrix,
  Set<String> collapsed,
  Set<String> pinnedIds,
  String query, [
  SpaceRoomsController? spaceRoomsController,
]) {
  // Single pass: collect subspace room IDs (for dedup) and count them.
  final subspaceRoomIds = <String>{};
  void collectSubspaces(List<SpaceNode> subs) {
    for (final sub in subs) {
      final subRooms = applySearch(matrix.roomsForSpace(sub.summary.roomId), query)
          .where((r) => !pinnedIds.contains(r.id));
      subspaceRoomIds.addAll(subRooms.map((r) => r.id));
      collectSubspaces(sub.subspaces);
    }
  }
  collectSubspaces(node.subspaces);

  final rooms = applySearch(matrix.roomsForSpace(node.summary.roomId), query)
      .where((r) => !pinnedIds.contains(r.id) &&
          !subspaceRoomIds.contains(r.id),)
      .toList();

  final totalRooms = rooms.length + subspaceRoomIds.length;

  // Always show subspace headers so users can see and manage newly created
  // (empty) subspaces. Only skip empty top-level space sections when there
  // are no matching unjoined rooms either.
  final hasMatchingUnjoined = spaceRoomsController != null &&
      _hasMatchingUnjoined(spaceRoomsController, node.summary.roomId, query);
  if (totalRooms == 0 &&
      node.subspaces.isEmpty &&
      depth == 0 &&
      !hasMatchingUnjoined) {
    return;
  }

  items.add(HeaderItem(
    name: node.summary.displayname,
    sectionKey: node.summary.roomId,
    depth: depth,
    roomCount: totalRooms,
    isSpace: true,
  ),);

  if (!collapsed.contains(node.summary.roomId)) {
    for (final room in rooms) {
      items.add(RoomItem(
        summary: matrix.summaryFor(room),
        depth: depth,
        parentSpaceId: node.summary.roomId,
        sectionRoomIds: rooms.map((r) => r.id).toList(),
      ),);
    }
    for (final sub in node.subspaces) {
      _addSpaceSection(
          items, sub, depth + 1, matrix, collapsed, pinnedIds, query,
          spaceRoomsController,);
    }
    _addUnjoinedGroup(items, node, depth, spaceRoomsController, query);
  }
}

void _addUnjoinedGroup(
  List<ListItem> items,
  SpaceNode node,
  int depth,
  SpaceRoomsController? controller,
  String query,
) {
  if (controller == null) return;

  final state = controller.getRoomState(node.summary.roomId);
  final q = query.toLowerCase();

  // Not yet fetched — show a slim loader.
  if (!controller.isCached(node.summary.roomId) || state.loading) {
    items.add(UnjoinedRoomLoadingItem(depth: depth));
    return;
  }

  // Error states.
  if (state.previewForbidden) {
    items.add(UnjoinedRoomForbiddenItem(depth: depth));
    return;
  }
  if (state.error != null) {
    items.add(UnjoinedRoomErrorItem(
      error: state.error!,
      spaceId: node.summary.roomId,
      depth: depth,
    ),);
    return;
  }

  // Filter by search query.
  bool metadataMatchesQuery(SpaceRoomMetadata m) {
    if (q.isEmpty) return true;
    final name = (m.name ?? m.roomId).toLowerCase();
    if (name.contains(q)) return true;
    return false;
  }

  final unjoinedRooms = state.unjoinedRooms
      .where(metadataMatchesQuery)
      .toList();
  final subspaces = state.subspaces
      .where(metadataMatchesQuery)
      .toList();

  // Nothing to show.
  if (unjoinedRooms.isEmpty && subspaces.isEmpty) return;

  // Group header.
  items.add(UnjoinedRoomGroupHeaderItem(
    spaceId: node.summary.roomId,
    unjoinedCount: unjoinedRooms.length + subspaces.length,
  ),);

  // Unjoined room tiles.
  for (final m in unjoinedRooms) {
    items.add(UnjoinedRoomItem(
      metadata: m,
      parentSpaceId: node.summary.roomId,
      depth: depth,
    ),);
  }

  // Unjoined subspace tiles with "Open" affordance.
  for (final m in subspaces) {
    items.add(SubspaceOpenItem(
      metadata: m,
      parentSpaceId: node.summary.roomId,
      depth: depth,
    ),);
  }
}

bool _hasMatchingUnjoined(
  SpaceRoomsController controller,
  String spaceId,
  String query,
) {
  if (!controller.isCached(spaceId)) return false;
  final state = controller.getRoomState(spaceId);
  if (state.loading || state.error != null || state.previewForbidden) {
    return true;
  }
  final q = query.toLowerCase();
  bool matches(SpaceRoomMetadata m) {
    if (q.isEmpty) return true;
    return (m.name ?? m.roomId).toLowerCase().contains(q);
  }
  return state.unjoinedRooms.any(matches) ||
      state.subspaces.any(matches);
}
