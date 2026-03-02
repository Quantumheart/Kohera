import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' hide Visibility;
import 'package:provider/provider.dart';

import '../services/matrix_service.dart';
import 'add_room_to_space_dialog.dart';

// ── Room Context Menu ───────────────────────────────────────────────

Future<void> showRoomContextMenu(
  BuildContext context,
  RelativeRect position,
  Room room,
) async {
  final matrix = context.read<MatrixService>();
  final cs = Theme.of(context).colorScheme;

  // Determine capabilities.
  final selectedIds = matrix.selectedSpaceIds;
  final memberships = matrix.spaceMemberships(room.id);

  // "Remove from space" — only when a space is selected and user has permission.
  Room? activeSpace;
  bool canRemove = false;
  if (selectedIds.isNotEmpty) {
    activeSpace = matrix.client.getRoomById(selectedIds.first);
    if (activeSpace != null &&
        activeSpace.canChangeStateEvent('m.space.child')) {
      canRemove = true;
    }
  }

  // "Add to space" — when there are eligible spaces the room isn't already in.
  final canAdd = matrix.spaces.any((s) =>
      s.canChangeStateEvent('m.space.child') &&
      !memberships.contains(s.id));

  if (!canAdd && !canRemove) return;

  final action = await showMenu<String>(
    context: context,
    position: position,
    color: cs.surfaceContainer,
    constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
    items: [
      if (canAdd)
        const PopupMenuItem(
          value: 'add_to_space',
          child: Row(
            children: [
              Icon(Icons.add_link_rounded, size: 18),
              SizedBox(width: 8),
              Text('Add to space'),
            ],
          ),
        ),
      if (canRemove)
        PopupMenuItem(
          value: 'remove_from_space',
          child: Row(
            children: [
              Icon(Icons.link_off_rounded, size: 18, color: cs.error),
              const SizedBox(width: 8),
              Text('Remove from space', style: TextStyle(color: cs.error)),
            ],
          ),
        ),
    ],
  );

  if (action == null || !context.mounted) return;

  switch (action) {
    case 'add_to_space':
      await AddRoomToSpaceDialog.show(
        context,
        room: room,
        matrixService: matrix,
      );
    case 'remove_from_space':
      if (activeSpace != null) {
        await _handleRemoveFromSpace(context, activeSpace, room);
      }
  }
}

// ── Action Handlers ─────────────────────────────────────────────────

Future<void> _handleRemoveFromSpace(
  BuildContext context,
  Room space,
  Room room,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Remove from space?'),
      content: Text(
        'Remove "${room.getLocalizedDisplayname()}" from '
        '"${space.getLocalizedDisplayname()}"? The room won\'t be deleted, '
        'just unlinked from the space.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  try {
    final matrix = context.read<MatrixService>();
    await space.removeSpaceChild(room.id);
    matrix.invalidateSpaceTree();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove room: $e')),
      );
    }
  }
}
