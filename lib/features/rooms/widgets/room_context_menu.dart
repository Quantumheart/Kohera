import 'package:flutter/material.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/core/utils/confirm_dialog.dart';
import 'package:kohera/features/rooms/services/room_context_menu_actions.dart';
import 'package:kohera/features/rooms/widgets/add_room_to_space_dialog.dart';
import 'package:kohera/shared/widgets/popup_menu_item_row.dart';
import 'package:kohera/shared/widgets/report_content_dialog.dart';
import 'package:provider/provider.dart';

// ── Room Context Menu ───────────────────────────────────────────────

enum _RoomContextAction { addToSpace, removeFromSpace, moveUp, moveDown, reportRoom }

/// Shows a context menu for a room in the room list.
///
/// This function reads [MatrixService] and [SelectionService] from context
/// and delegates SDK operations to [RoomContextMenuActions].
Future<void> showRoomContextMenu(
  BuildContext context,
  RelativeRect position,
  String roomId, {
  String? parentSpaceId,
  List<String>? sectionRoomIds,
}) async {
  final selection = context.read<SelectionService>();
  final matrix = context.read<MatrixService>();
  final actions = RoomContextMenuActions(matrix: matrix, selection: selection);
  final cs = Theme.of(context).colorScheme;

  final (:canRemove, :activeSpaceId) = actions.checkSelectedSpaces();
  final canAdd = actions.canAddToSpace(roomId);

  String? reorderSpaceId;
  List<String>? orderedRoomIds;
  var roomIndex = -1;
  if (parentSpaceId != null && sectionRoomIds != null) {
    if (actions.canManageSpaceChildren(parentSpaceId)) {
      reorderSpaceId = parentSpaceId;
      orderedRoomIds = sectionRoomIds;
      roomIndex = orderedRoomIds.indexOf(roomId);
    }
  }

  final canMoveUp = reorderSpaceId != null && roomIndex > 0;
  final canMoveDown = reorderSpaceId != null &&
      orderedRoomIds != null &&
      roomIndex >= 0 &&
      roomIndex < orderedRoomIds.length - 1;
  final canReport = matrix.client.getRoomById(roomId)?.lastEvent != null;

  if (!canAdd && !canRemove && !canMoveUp && !canMoveDown && !canReport) return;

  final activeSpaceName =
      activeSpaceId != null ? actions.roomDisplayName(activeSpaceId) : null;

  final action = await showMenu<_RoomContextAction>(
    context: context,
    position: position,
    color: cs.surfaceContainer,
    constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
    items: [
      if (canMoveUp)
        menuItemRow(
          Icons.arrow_upward_rounded,
          'Move up',
          _RoomContextAction.moveUp,
        ),
      if (canMoveDown)
        menuItemRow(
          Icons.arrow_downward_rounded,
          'Move down',
          _RoomContextAction.moveDown,
        ),
      if (canAdd)
        menuItemRow(
          Icons.add_link_rounded,
          'Add to space',
          _RoomContextAction.addToSpace,
        ),
      if (canRemove && activeSpaceName != null)
        PopupMenuItem(
          value: _RoomContextAction.removeFromSpace,
          child: Row(
            children: [
              Icon(Icons.link_off_rounded, size: 18, color: cs.error),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Remove from $activeSpaceName',
                  style: TextStyle(color: cs.error),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      if (canReport)
        menuItemRow(
          Icons.flag_outlined,
          'Report room',
          _RoomContextAction.reportRoom,
          color: cs.error,
        ),
    ],
  );

  if (action == null || !context.mounted) return;

  switch (action) {
    case _RoomContextAction.addToSpace:
      await AddRoomToSpaceDialog.show(
        context,
        roomId: roomId,
        candidateSpaces: selection.spaces
            .where((s) => s.canChangeStateEvent('m.space.child'))
            .map(selection.summaryFor)
            .toList(),
        memberSpaceIds: selection.spaceMemberships(roomId),
        avatarResolver: matrix.avatarResolver,
        onAddToSpaces: (selections) =>
            actions.addToSpaces(roomId, selections),
      );
    case _RoomContextAction.removeFromSpace:
      if (activeSpaceId != null) {
        await _handleRemoveFromSpace(context, actions, activeSpaceId, roomId);
      }
    case _RoomContextAction.moveUp:
      if (reorderSpaceId != null &&
          orderedRoomIds != null &&
          roomIndex > 0) {
        await _handleReorder(
          context,
          actions,
          reorderSpaceId,
          orderedRoomIds,
          roomIndex,
          roomIndex - 1,
        );
      }
    case _RoomContextAction.moveDown:
      if (reorderSpaceId != null &&
          orderedRoomIds != null &&
          roomIndex < orderedRoomIds.length - 1) {
        await _handleReorder(
          context,
          actions,
          reorderSpaceId,
          orderedRoomIds,
          roomIndex,
          roomIndex + 1,
        );
      }
    case _RoomContextAction.reportRoom:
      if (context.mounted) {
        await reportRoomContent(context, matrix.client, roomId);
      }
  }
}

// ── Action Handlers ─────────────────────────────────────────────────

Future<void> _handleReorder(
  BuildContext context,
  RoomContextMenuActions actions,
  String spaceId,
  List<String> orderedRoomIds,
  int fromIndex,
  int toIndex,
) async {
  try {
    await actions.reorder(spaceId, orderedRoomIds, fromIndex, toIndex);
  } catch (e) {
    debugPrint('[Kohera] Reorder failed: $e');
    if (context.mounted) context.showSnack('Failed to reorder: $e');
  }
}

Future<void> _handleRemoveFromSpace(
  BuildContext context,
  RoomContextMenuActions actions,
  String spaceId,
  String roomId,
) async {
  final spaceName = actions.roomDisplayName(spaceId) ?? spaceId;
  final roomName = actions.roomDisplayName(roomId) ?? roomId;
  final confirmed = await confirmDialog(
    context,
    title: 'Remove from space?',
    message: 'Remove "$roomName" from '
        '"$spaceName"? The room won\'t be deleted, '
        'just unlinked from the space.',
    confirmLabel: 'Remove',
  );

  if (!confirmed || !context.mounted) return;

  try {
    await actions.removeFromSpace(spaceId, roomId);
  } catch (e) {
    if (context.mounted) context.showSnack('Failed to remove room: $e');
  }
}
