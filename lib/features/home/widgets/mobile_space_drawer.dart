import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/client_avatar_resolver.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/core/theme/k_icons.dart';
import 'package:kohera/features/rooms/widgets/invite_dialog.dart';
import 'package:kohera/features/spaces/widgets/space_action_dialog.dart';
import 'package:kohera/features/spaces/widgets/space_context_menu.dart';
import 'package:kohera/shared/models/kohera_room_summary.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/room_avatar.dart';
import 'package:provider/provider.dart';
Future<void> _showAddSpaceChooser(BuildContext context) async {
  final cs = Theme.of(context).colorScheme;
  final action = await showDialog<SpaceAction>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Add space'),
      children: [
        for (final entry in spaceActionEntries)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, entry.action),
            child: Row(
              children: [
                Icon(entry.icon, color: cs.primary),
                const SizedBox(width: 16),
                Text(entry.label),
              ],
            ),
          ),
      ],
    ),
  );

  if (action == null || !context.mounted) return;
  Navigator.of(context).pop();
  if (!context.mounted) return;
  await runSpaceAction(context, action);
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
                child: Icon(KIcons.homeRounded, color: cs.onPrimaryContainer),
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
                      spaceId: space.id,
                      summary: selection.summaryFor(space),
                      avatarResolver: ClientAvatarResolver(space.client),
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
                          space.id,
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
                          child: RoomAvatarWidget(
                          avatarUrl: selection.summaryFor(space).avatarUrl,
                          displayname: selection.summaryFor(space).displayname,
                          avatarResolver: ClientAvatarResolver(space.client),
                          size: 36,
                        ),
                        ),
                        title: Text(selection.summaryFor(space).displayname),
                        onTap: () async {
                          final result = await InviteDialog.show(
                            context,
                            roomId: space.id,
                            summary: selection.summaryFor(space),
                            inviterName: selection.inviterDisplayName(space),
                            onAccept: space.join,
                            onDecline: space.leave,
                          );
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
              leading: Icon(KIcons.addCircleOutline, color: cs.primary),
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
    required this.spaceId,
    required this.summary,
    required this.avatarResolver,
    required this.selected,
    required this.unread,
    required this.onTap,
    this.onMenuRequested,
  });

  final String spaceId;
  final KoheraRoomSummary summary;
  final AvatarResolver avatarResolver;
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
              borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
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
              icon: const Icon(KIcons.moreVert),
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
            leading: RoomAvatarWidget(
                          avatarUrl: summary.avatarUrl,
                          displayname: summary.displayname,
                          avatarResolver: avatarResolver,
                          size: 36,
                        ),
            title: Text(summary.displayname),
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
