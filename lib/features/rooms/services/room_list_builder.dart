import 'package:kohera/core/models/space_node.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/rooms/widgets/room_list_models.dart';
import 'package:kohera/features/spaces/models/space_rooms_model.dart';
import 'package:kohera/features/spaces/services/space_rooms_controller.dart';
import 'package:kohera/shared/models/kohera_room_summary.dart';

// ── Section-building helpers for the room list ──────────

bool roomSummaryMatchesQuery(KoheraRoomSummary s, String q) {
  if (s.displayname.toLowerCase().contains(q)) return true;

  final alias = s.canonicalAlias;
  if (alias != null && alias.toLowerCase().contains(q)) return true;

  final dmPartner = s.dmUserId;
  if (dmPartner != null && dmPartner.toLowerCase().contains(q)) return true;

  return false;
}

List<KoheraRoomSummary> applySearch(
  List<KoheraRoomSummary> summaries,
  String query,
) {
  if (query.isEmpty) return summaries;
  final q = query.toLowerCase();
  return summaries.where((s) => roomSummaryMatchesQuery(s, q)).toList();
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

  final invitedSummaries =
      applySearch(matrix.invitedRooms.map(matrix.summaryFor).toList(), query);
  for (final summary in invitedSummaries) {
    items.add(InviteItem(summary: summary));
  }

  final pinnedIds = <String>{};

  if (selectedIds.isNotEmpty) {
    final visibleNodes =
        tree.where((n) => selectedIds.contains(n.summary.roomId)).toList();
    for (final node in visibleNodes) {
      _addSpaceSection(
        items,
        node,
        0,
        matrix,
        collapsed,
        pinnedIds,
        query,
        spaceRoomsController,
      );
    }
  } else {
    final pinnedSummaries = applySearch(
      matrix.rooms.where((r) => r.isFavourite).map(matrix.summaryFor).toList(),
      query,
    );
    pinnedIds.addAll(pinnedSummaries.map((s) => s.roomId));
    if (pinnedSummaries.isNotEmpty) {
      items.add(
        HeaderItem(
          name: 'Pinned',
          sectionKey: PreferencesService.pinnedSectionKey,
          depth: 0,
          roomCount: pinnedSummaries.length,
        ),
      );
      if (!collapsed.contains(PreferencesService.pinnedSectionKey)) {
        for (final summary in pinnedSummaries) {
          items.add(RoomItem(summary: summary));
        }
      }
    }

    final dmSummaries = applySearch(
      matrix.rooms
          .where(
            (r) => r.isDirectChat && !pinnedIds.contains(r.id),
          )
          .map(matrix.summaryFor)
          .toList(),
      query,
    );
    if (dmSummaries.isNotEmpty) {
      items.add(
        HeaderItem(
          name: 'Direct Messages',
          sectionKey: PreferencesService.dmSectionKey,
          depth: 0,
          roomCount: dmSummaries.length,
        ),
      );
      if (!collapsed.contains(PreferencesService.dmSectionKey)) {
        for (final summary in dmSummaries) {
          items.add(RoomItem(summary: summary));
        }
      }
    }

    final orphanSummaries = applySearch(
      matrix.orphanRooms
          .where(
            (r) => !pinnedIds.contains(r.id) && !r.isDirectChat,
          )
          .map(matrix.summaryFor)
          .toList(),
      query,
    );
    if (orphanSummaries.isNotEmpty) {
      items.add(
        HeaderItem(
          name: 'Rooms',
          sectionKey: PreferencesService.unsortedSectionKey,
          depth: 0,
          roomCount: orphanSummaries.length,
        ),
      );
      if (!collapsed.contains(PreferencesService.unsortedSectionKey)) {
        for (final summary in orphanSummaries) {
          items.add(RoomItem(summary: summary));
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
  final subspaceRoomIds = <String>{};
  void collectSubspaces(List<SpaceNode> subs) {
    for (final sub in subs) {
      final subRooms = applySearch(
        matrix
            .roomsForSpace(sub.summary.roomId)
            .map(matrix.summaryFor)
            .toList(),
        query,
      ).where((s) => !pinnedIds.contains(s.roomId));
      subspaceRoomIds.addAll(subRooms.map((s) => s.roomId));
      collectSubspaces(sub.subspaces);
    }
  }

  collectSubspaces(node.subspaces);

  final rooms = applySearch(
    matrix.roomsForSpace(node.summary.roomId).map(matrix.summaryFor).toList(),
    query,
  )
      .where(
        (s) =>
            !pinnedIds.contains(s.roomId) &&
            !subspaceRoomIds.contains(s.roomId),
      )
      .toList();

  final totalRooms = rooms.length + subspaceRoomIds.length;

  final hasMatchingUnjoined = spaceRoomsController != null &&
      _hasMatchingUnjoined(spaceRoomsController, node.summary.roomId, query);
  if (totalRooms == 0 &&
      node.subspaces.isEmpty &&
      depth == 0 &&
      !hasMatchingUnjoined) {
    return;
  }

  items.add(
    HeaderItem(
      name: node.summary.displayname,
      sectionKey: node.summary.roomId,
      depth: depth,
      roomCount: totalRooms,
      isSpace: true,
    ),
  );

  if (!collapsed.contains(node.summary.roomId)) {
    for (final summary in rooms) {
      items.add(
        RoomItem(
          summary: summary,
          depth: depth,
          parentSpaceId: node.summary.roomId,
          sectionRoomIds: rooms.map((s) => s.roomId).toList(),
        ),
      );
    }
    for (final sub in node.subspaces) {
      _addSpaceSection(
        items,
        sub,
        depth + 1,
        matrix,
        collapsed,
        pinnedIds,
        query,
        spaceRoomsController,
      );
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

  if (!controller.isCached(node.summary.roomId) || state.loading) {
    items.add(UnjoinedRoomLoadingItem(depth: depth));
    return;
  }

  if (state.previewForbidden) {
    items.add(UnjoinedRoomForbiddenItem(depth: depth));
    return;
  }
  if (state.error != null) {
    items.add(
      UnjoinedRoomErrorItem(
        error: state.error!,
        spaceId: node.summary.roomId,
        depth: depth,
      ),
    );
    return;
  }

  bool metadataMatchesQuery(SpaceRoomMetadata m) {
    if (q.isEmpty) return true;
    return (m.name ?? m.roomId).toLowerCase().contains(q);
  }

  final unjoinedRooms =
      state.unjoinedRooms.where(metadataMatchesQuery).toList();
  final subspaces = state.subspaces.where(metadataMatchesQuery).toList();

  if (unjoinedRooms.isEmpty && subspaces.isEmpty) return;

  items.add(
    UnjoinedRoomGroupHeaderItem(
      spaceId: node.summary.roomId,
      unjoinedCount: unjoinedRooms.length + subspaces.length,
    ),
  );

  for (final m in unjoinedRooms) {
    items.add(
      UnjoinedRoomItem(
        metadata: m,
        parentSpaceId: node.summary.roomId,
        depth: depth,
      ),
    );
  }

  for (final m in subspaces) {
    items.add(
      SubspaceOpenItem(
        metadata: m,
        parentSpaceId: node.summary.roomId,
        depth: depth,
      ),
    );
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

  return state.unjoinedRooms.any(matches) || state.subspaces.any(matches);
}
