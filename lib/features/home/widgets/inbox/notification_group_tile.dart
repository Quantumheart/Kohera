import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/client_avatar_resolver.dart';
import 'package:kohera/core/theme/k_icons.dart';
import 'package:kohera/features/home/widgets/inbox/sub_group_section.dart';
import 'package:kohera/features/notifications/models/notification_constants.dart';
import 'package:kohera/features/notifications/models/notification_group.dart';
import 'package:kohera/features/notifications/services/inbox_controller.dart';
import 'package:kohera/shared/widgets/room_avatar.dart';
class NotificationGroupTile extends StatelessWidget {
  const NotificationGroupTile({
    required this.group,
    required this.controller,
    super.key,
  });

  final NotificationGroup group;
  final InboxController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final client = controller.client;
    final room = client.getRoomById(group.roomId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 0,
        color: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Group header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
              child: Row(
                children: [
                  if (room != null) ...[
                    RoomAvatarWidget(
                      avatarUrl: room.avatar?.toString(),
                      displayname: room.getLocalizedDisplayname(),
                      avatarResolver: ClientAvatarResolver(room.client),
                      size: 32,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      group.roomName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(KIcons.doneAllRounded, size: 20),
                    tooltip: InboxText.tooltipMarkAsRead,
                    onPressed: () => controller.markRoomAsRead(group.roomId),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(KIcons.openInNewRounded, size: 20),
                    tooltip: InboxText.tooltipOpen,
                    onPressed: () {
                      final singleThread = group.subGroups.length == 1
                          ? group.subGroups.first.threadRootId
                          : null;
                      if (singleThread != null) {
                        context.goNamed(
                          Routes.roomThread,
                          pathParameters: {
                            RouteParams.roomId: group.roomId,
                            RouteParams.eventId: singleThread,
                          },
                        );
                      } else {
                        context.goNamed(
                          Routes.room,
                          pathParameters: {RouteParams.roomId: group.roomId},
                        );
                      }
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── Sub-groups (per-thread + main) ──
            for (final sub in group.subGroups)
              SubGroupSection(
                roomId: group.roomId,
                subGroup: sub,
                controller: controller,
              ),
          ],
        ),
      ),
    );
  }
}
