import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/features/rooms/widgets/invite_dialog.dart';
import 'package:kohera/features/spaces/widgets/space_action_dialog.dart';
import 'package:kohera/features/spaces/widgets/space_context_menu.dart';
import 'package:kohera/shared/widgets/room_avatar.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

enum _AddSpaceAction { create, join, discover }

Future<void> _showAddSpaceChooser(BuildContext context) async {
  final cs = Theme.of(context).colorScheme;
  final action = await showDialog<_AddSpaceAction>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Add space'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, _AddSpaceAction.create),
          child: Row(
            children: [
              Icon(Icons.add_circle_outline, color: cs.primary),
              const SizedBox(width: 16),
              const Text('Create space'),
            ],
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, _AddSpaceAction.join),
          child: Row(
            children: [
              Icon(Icons.tag, color: cs.primary),
              const SizedBox(width: 16),
              const Text('Join with address'),
            ],
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, _AddSpaceAction.discover),
          child: Row(
            children: [
              Icon(Icons.travel_explore, color: cs.primary),
              const SizedBox(width: 16),
              const Text('Explore spaces'),
            ],
          ),
        ),
      ],
    ),
  );

  if (action == null || !context.mounted) return;
  final matrix = context.read<MatrixService>();
  Navigator.of(context).pop();
  switch (action) {
    case _AddSpaceAction.create:
      await CreateSpaceDialog.show(context, matrixService: matrix);
    case _AddSpaceAction.join:
      await JoinSpaceDialog.show(context, matrixService: matrix);
    case _AddSpaceAction.discover:
      await SpaceDiscoveryDialog.show(context, matrixService: matrix);
  }
}

class MobileSpaceDrawer extends StatelessWidget {
  const MobileSpaceDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<SelectionService>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final topLevel = selection.topLevelSpaces;
    final invited = selection.invitedSpaces;
    final homeSelected = selection.selectedSpaceIds.isEmpty;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Spaces',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.home_rounded, color: cs.onPrimaryContainer),
              ),
              title: const Text('Home'),
              selected: homeSelected,
              onTap: () {
                selection.clearSpaceSelection();
                Navigator.of(context).pop();
                context.goNamed(Routes.home);
              },
            ),
            const Divider(height: 8),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final space in topLevel)
                    _SpaceTile(
                      space: space,
                      selected: selection.selectedSpaceIds.contains(space.id),
                      unread: selection.unreadCountForSpace(space.id),
                      onTap: () {
                        selection.selectSpace(space.id);
                        Navigator.of(context).pop();
                        context.goNamed(Routes.home);
                      },
                      onMenuRequested: (anchorContext) {
                        final box =
                            anchorContext.findRenderObject()! as RenderBox;
                        final overlay = Overlay.of(anchorContext)
                            .context
                            .findRenderObject()! as RenderBox;
                        final position = box.localToGlobal(
                          Offset(box.size.width / 2, box.size.height / 2),
                          ancestor: overlay,
                        );
                        unawaited(showSpaceContextMenu(
                          anchorContext,
                          RelativeRect.fromSize(
                              position & Size.zero, overlay.size,),
                          space,
                        ),);
                      },
                    ),
                  if (invited.isNotEmpty) ...[
                    const Divider(height: 8),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                      child: Text(
                        'Invited',
                        style: tt.labelLarge?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    for (final space in invited)
                      ListTile(
                        leading: Opacity(
                          opacity: 0.7,
                          child: RoomAvatarWidget(room: space, size: 36),
                        ),
                        title: Text(space.getLocalizedDisplayname()),
                        onTap: () async {
                          final result =
                              await InviteDialog.show(context, room: space);
                          if (result == true && context.mounted) {
                            selection.selectSpace(space.id);
                            if (context.mounted) {
                              Navigator.of(context).pop();
                              context.goNamed(Routes.home);
                            }
                          }
                        },
                      ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.add_circle_outline, color: cs.primary),
              title: const Text('Add space'),
              subtitle: const Text('Create, join, or explore'),
              onTap: () => unawaited(_showAddSpaceChooser(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpaceTile extends StatelessWidget {
  const _SpaceTile({
    required this.space,
    required this.selected,
    required this.unread,
    required this.onTap,
    this.onMenuRequested,
  });

  final Room space;
  final bool selected;
  final int unread;
  final VoidCallback onTap;
  final void Function(BuildContext anchorContext)? onMenuRequested;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Builder(
      builder: (tileContext) {
        Widget? trailing;
        if (unread > 0) {
          trailing = Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              unread > 99 ? '99+' : '$unread',
              style: TextStyle(
                color: cs.onPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }
        if (onMenuRequested != null) {
          final menuButton = Builder(
            builder: (btnContext) => IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Space options',
              onPressed: () => onMenuRequested!(btnContext),
            ),
          );
          trailing = trailing == null
              ? menuButton
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [trailing, const SizedBox(width: 4), menuButton],
                );
        }

        return GestureDetector(
          onSecondaryTapUp: onMenuRequested == null
              ? null
              : (_) => onMenuRequested!(tileContext),
          child: ListTile(
            leading: RoomAvatarWidget(room: space, size: 36),
            title: Text(space.getLocalizedDisplayname()),
            selected: selected,
            trailing: trailing,
            onTap: onTap,
            onLongPress: onMenuRequested == null
                ? null
                : () => onMenuRequested!(tileContext),
          ),
        );
      },
    );
  }
}
