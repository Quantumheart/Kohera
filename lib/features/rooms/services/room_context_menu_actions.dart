import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/core/utils/order_utils.dart' as order_utils;

/// SDK boundary for room context menu operations.
///
/// All Matrix SDK access (Room, Client, canChangeStateEvent, setSpaceChild,
/// etc.) is encapsulated here. The [RoomContextMenu] widget calls these
/// methods without importing `package:matrix/matrix.dart`.
class RoomContextMenuActions {
  RoomContextMenuActions({required this.matrix, required this.selection});

  final MatrixService matrix;
  final SelectionService selection;

  /// Returns the display name of [roomId], or `null` if the room is not
  /// found.
  String? roomDisplayName(String roomId) {
    final room = matrix.client.getRoomById(roomId);
    return room?.getLocalizedDisplayname();
  }

  /// Whether the room with [spaceId] allows the current user to manage
  /// space children (add/remove/reorder).
  bool canManageSpaceChildren(String spaceId) {
    final space = matrix.client.getRoomById(spaceId);
    if (space == null) return false;
    return space.canChangeStateEvent('m.space.child');
  }

  /// Whether any of the selected spaces allows managing children.
  ({bool canRemove, String? activeSpaceId}) checkSelectedSpaces() {
    for (final spaceId in selection.selectedSpaceIds) {
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
      final space = matrix.client.getRoomById(entry.key);
      if (space == null) continue;
      try {
        await space.setSpaceChild(
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
    final space = matrix.client.getRoomById(spaceId);
    if (space == null) return;
    await space.removeSpaceChild(roomId);
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
    final space = matrix.client.getRoomById(spaceId);
    if (space == null) return;

    final roomId = orderedRoomIds[fromIndex];
    final orderMap = order_utils.buildOrderMap(space);

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

    await space.setSpaceChild(roomId, order: newOrder);
    selection.invalidateSpaceTree();
  }
}
