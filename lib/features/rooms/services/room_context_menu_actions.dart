import 'package:flutter/foundation.dart';
import 'package:kohera/core/state/selection_controller.dart';
import 'package:kohera/core/utils/order_utils.dart' as order_utils;
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/data/repositories/space_tree_repository.dart';

/// SDK boundary for room context menu operations.
///
/// All Matrix SDK access (Room, canChangeStateEvent, setSpaceChild, etc.) is
/// encapsulated here via [RoomRepository]. The [RoomContextMenu] widget calls
/// these methods without importing `package:matrix/matrix.dart`.
class RoomContextMenuActions {
  RoomContextMenuActions({
    required this.rooms,
    required this.selection,
    required this.selectionState,
  });

  final RoomRepository rooms;
  final SpaceTreeRepository selection;
  final SelectionController selectionState;

  /// Returns the display name of [roomId], or `null` if the room is not
  /// found.
  String? roomDisplayName(String roomId) {
    if (!rooms.roomExists(roomId)) return null;
    return rooms.displayNameFor(roomId);
  }

  /// Whether the room with [spaceId] allows the current user to manage
  /// space children (add/remove/reorder).
  bool canManageSpaceChildren(String spaceId) =>
      rooms.canChangeStateEventOf(spaceId, 'm.space.child');

  /// Whether any of the selected spaces allows managing children.
  ({bool canRemove, String? activeSpaceId}) checkSelectedSpaces() {
    for (final spaceId in selectionState.selectedSpaceIds) {
      if (canManageSpaceChildren(spaceId)) {
        return (canRemove: true, activeSpaceId: spaceId);
      }
    }
    return (canRemove: false, activeSpaceId: null);
  }

  /// Whether any space can have [roomId] added (not already a member).
  bool canAddToSpace(String roomId) {
    final memberships = selection.spaceMemberships(roomId);
    return selection.spaces.any(
      (s) =>
          s.canChangeStateEvent('m.space.child') &&
          !memberships.contains(s.id),
    );
  }

  /// Adds [roomId] to each selected space in [selections].
  /// [selections] maps space ID → suggested flag.
  /// Returns the number of failures.
  Future<int> addToSpaces(
    String roomId,
    Map<String, bool> selections,
  ) async {
    var failures = 0;
    for (final entry in selections.entries) {
      if (!rooms.roomExists(entry.key)) continue;
      try {
        await rooms.setSpaceChild(
          entry.key,
          roomId,
          suggested: entry.value ? true : null,
        );
      } catch (e) {
        debugPrint('[Kohera] Failed to add room to space: $e');
        failures++;
      }
    }
    selection.invalidateSpaceTree();
    return failures;
  }

  /// Removes [roomId] from the space [spaceId].
  Future<void> removeFromSpace(String spaceId, String roomId) async {
    if (!rooms.roomExists(spaceId)) return;
    await rooms.removeSpaceChild(spaceId, roomId);
    selection.invalidateSpaceTree();
  }

  /// Reorders [roomId] within [spaceId] from [fromIndex] to [toIndex]
  /// in [orderedRoomIds].
  Future<void> reorder(
    String spaceId,
    List<String> orderedRoomIds,
    int fromIndex,
    int toIndex,
  ) async {
    if (!rooms.roomExists(spaceId)) return;

    final roomId = orderedRoomIds[fromIndex];
    final orderMap = rooms.spaceChildOrderMap(spaceId);

    final String? neighborBefore;
    final String? neighborAfter;
    if (toIndex < fromIndex) {
      neighborBefore =
          toIndex > 0 ? orderMap[orderedRoomIds[toIndex - 1]] : null;
      neighborAfter = orderMap[orderedRoomIds[toIndex]];
    } else {
      neighborBefore = orderMap[orderedRoomIds[toIndex]];
      neighborAfter = toIndex + 1 < orderedRoomIds.length
          ? orderMap[orderedRoomIds[toIndex + 1]]
          : null;
    }

    final newOrder = order_utils.midpoint(neighborBefore, neighborAfter);
    if (newOrder == null) {
      debugPrint('[Kohera] Could not compute order midpoint');
      return;
    }

    await rooms.setSpaceChild(spaceId, roomId, order: newOrder);
    selection.invalidateSpaceTree();
  }
}
