import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/data/models/kohera_push_rule_state.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/data/repositories/space_repository.dart';
import 'package:kohera/data/repositories/user_repository.dart';
import 'package:kohera/features/rooms/services/invite_user_dialog_params.dart';
import 'package:kohera/features/rooms/widgets/add_existing_rooms_dialog.dart';
import 'package:kohera/features/rooms/widgets/invite_user_dialog.dart';
import 'package:kohera/features/rooms/widgets/new_room_dialog.dart';
import 'package:kohera/features/spaces/widgets/create_subspace_action.dart';
import 'package:kohera/features/spaces/widgets/create_subspace_dialog.dart';
import 'package:kohera/features/spaces/widgets/notification_radio_group.dart';
import 'package:kohera/features/spaces/widgets/space_details_panel.dart'
    show SpaceDetailsPanel;
import 'package:kohera/shared/widgets/popup_menu_item_row.dart';
import 'package:kohera/shared/widgets/report_content_dialog.dart';
import 'package:provider/provider.dart';

// ── Space Context Menu ──────────────────────────────────────────────

enum SpaceContextAction {
  markAsRead,
  invitePeople,
  spaceSettings,
  createRoom,
  createSubspace,
  addExistingRoom,
  notifications,
  leaveSpace,
  reportRoom,
}

Future<void> showSpaceContextMenu(
  BuildContext context,
  RelativeRect position,
  String spaceId,
) async {
  final cs = Theme.of(context).colorScheme;
  final matrix = context.read<MatrixService>();
  final spaceRepo = context.read<SpaceRepository>();
  final roomRepo = context.read<RoomRepository>();
  final userRepo = context.read<UserRepository>();

  final canInvite = spaceRepo.canInvite(spaceId);
  final canManageChildren = spaceRepo.canManageChildren(spaceId);
  final canEditName = spaceRepo.canEditName(spaceId);
  final canReport = roomRepo.lastEventId(spaceId) != null;

  final action = await showMenu<SpaceContextAction>(
    context: context,
    position: position,
    color: cs.surfaceContainer,
    constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
    items: [
      menuItemRow(
        Icons.done_all_rounded, 'Mark as read', SpaceContextAction.markAsRead,),
      if (canInvite)
        menuItemRow(
          Icons.person_add_outlined,
          'Invite people',
          SpaceContextAction.invitePeople,
        ),
      if (canEditName)
        menuItemRow(
          Icons.settings_outlined,
          'Space settings',
          SpaceContextAction.spaceSettings,
        ),
      if (canManageChildren) ...[
        menuItemRow(
          Icons.add_rounded, 'Create room', SpaceContextAction.createRoom,),
        menuItemRow(
          Icons.workspaces_outlined,
          'Create subspace',
          SpaceContextAction.createSubspace,
        ),
        menuItemRow(
          Icons.link_rounded,
          'Add existing room',
          SpaceContextAction.addExistingRoom,
        ),
      ],
      menuItemRow(
        Icons.notifications_outlined,
        'Notifications',
        SpaceContextAction.notifications,
      ),
      if (canReport)
        menuItemRow(
          Icons.flag_outlined,
          'Report room',
          SpaceContextAction.reportRoom,
          color: cs.error,
        ),
      const PopupMenuDivider(),
      menuItemRow(
        Icons.logout_rounded,
        'Leave space',
        SpaceContextAction.leaveSpace,
        color: cs.error,
      ),
    ],
  );

  if (action == null || !context.mounted) return;

  switch (action) {
    case SpaceContextAction.markAsRead:
      await spaceRepo.markAsRead(spaceId);
    case SpaceContextAction.invitePeople:
      if (context.mounted) await _handleInvite(context, spaceRepo, spaceId);
    case SpaceContextAction.leaveSpace:
      if (context.mounted) await _handleLeave(context, spaceRepo, spaceId);
    case SpaceContextAction.addExistingRoom:
      if (context.mounted) {
        await AddExistingRoomsDialog.show(
          context,
          candidateRooms: spaceRepo.joinedRoomSummaries(),
          existingChildIds: spaceRepo.existingChildIds(spaceId),
          avatarResolver: matrix.avatarResolver,
          onAddRooms: (roomIds) async {
            var failures = 0;
            for (final id in roomIds) {
              try {
                await spaceRepo.setSpaceChild(spaceId, id);
              } catch (e) {
                debugPrint('[Kohera] Failed to add room to space: $e');
                failures++;
              }
            }
            spaceRepo.invalidateSpaceTree();
            return failures;
          },
        );
      }
    case SpaceContextAction.createRoom:
      if (context.mounted) {
        await NewRoomDialog.show(
          context,
          matrixService: matrix,
          parentSpaceIds: {spaceId},
        );
      }
    case SpaceContextAction.spaceSettings:
      if (context.mounted) {
        context.goNamed(
          Routes.spaceDetails,
          pathParameters: {RouteParams.spaceId: spaceId},
        );
      }
    case SpaceContextAction.createSubspace:
      if (context.mounted) {
        await CreateSubspaceDialog.show(
          context,
          parentSpaceRef: (
            id: spaceId,
            displayname: spaceRepo.spaceDisplayname(spaceId),
          ),
          loadCapabilities: () => loadSubspaceCapabilities(spaceRepo),
          onCreateSubspace: (request) => spaceRepo.createSubspace(
            parentSpaceId: spaceId,
            name: request.name,
            topic: request.topic,
            joinMode: request.joinMode,
            allowedSpaceIds: request.allowedSpaceIds,
            restrictedRoomVersion: request.restrictedRoomVersion,
          ),
        );
      }
    case SpaceContextAction.notifications:
      if (context.mounted) {
        await _handleNotifications(context, spaceRepo, spaceId);
      }
    case SpaceContextAction.reportRoom:
      if (context.mounted) {
        await reportRoomContent(context, roomRepo, userRepo, spaceId);
      }
  }
}

// ── Action Handlers ─────────────────────────────────────────────────

/// Shows a leave-space confirmation dialog with an option to also leave
/// all child rooms. Reused by [SpaceDetailsPanel].
Future<void> handleLeaveSpace(BuildContext context, String spaceId) async {
  await _handleLeave(context, context.read<SpaceRepository>(), spaceId);
}

Future<void> _handleNotifications(
  BuildContext context,
  SpaceRepository spaceRepo,
  String spaceId,
) async {
  final current = spaceRepo.pushRuleState(spaceId);
  final result = await showDialog<KoheraPushRuleState>(
    context: context,
    builder: (ctx) {
      var selected = current;
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Space notifications'),
          content: NotificationRadioGroup(
            groupValue: selected,
            onChanged: (v) => setState(() => selected = v!),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('Save'),
            ),
          ],
        ),
      );
    },
  );

  if (result == null || result == current || !context.mounted) return;

  try {
    await spaceRepo.setPushRuleState(spaceId, result);
    if (context.mounted) context.showSnack('Notifications updated');
  } catch (e) {
    if (context.mounted) {
      context.showSnack('Failed to update notifications: $e');
    }
  }
}

Future<void> _handleInvite(
  BuildContext context,
  SpaceRepository spaceRepo,
  String spaceId,
) async {
  if (!spaceRepo.spaceExists(spaceId)) return;

  final mxid = await InviteUserDialog.show(
    context,
    params: inviteUserDialogParams(
      spaceId,
      context.read<RoomRepository>(),
      context.read<UserRepository>(),
    ),
  );

  if (mxid == null || !context.mounted) return;

  try {
    await spaceRepo.invite(spaceId, mxid);
    if (context.mounted) context.showSnack('Invited $mxid');
  } catch (e) {
    if (context.mounted) context.showSnack('Failed to invite: $e');
  }
}

Future<void> _handleLeave(
  BuildContext context,
  SpaceRepository spaceRepo,
  String spaceId,
) async {
  final cs = Theme.of(context).colorScheme;
  if (!spaceRepo.spaceExists(spaceId)) return;
  final displayname = spaceRepo.spaceDisplayname(spaceId);

  final result = await showDialog<({bool confirmed, bool leaveChildren})>(
    context: context,
    builder: (ctx) {
      var leaveChildren = false;
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Leave space?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('You will leave "$displayname".'),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: leaveChildren,
                onChanged: (v) => setState(() => leaveChildren = v ?? false),
                title: const Text('Also leave all rooms in this space'),
                subtitle: const Text(
                  'Rooms you stay in will move to your general room list.',
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
              ),
              onPressed: () => Navigator.pop(
                ctx,
                (confirmed: true, leaveChildren: leaveChildren),
              ),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
    },
  );

  if (result == null || !result.confirmed || !context.mounted) return;

  try {
    final failCount =
        await spaceRepo.leave(spaceId, leaveChildren: result.leaveChildren);
    if (failCount > 0 && context.mounted) {
      context.showSnack('Failed to leave $failCount room(s)');
    }
  } catch (e) {
    if (context.mounted) context.showSnack('Failed to leave space: $e');
  }
}
