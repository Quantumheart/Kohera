import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/theme/k_icons.dart';
import 'package:kohera/core/utils/time_format.dart';
import 'package:kohera/features/notifications/models/kohera_notification_item.dart';
import 'package:kohera/features/notifications/models/notification_constants.dart';
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    required this.item,
    required this.threadRootId,
    super.key,
  });

  final KoheraNotificationItem item;
  final String? threadRootId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final body = item.body;
    final ts = DateTime.fromMillisecondsSinceEpoch(item.timestamp);

    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      canRequestFocus: false,
      onTap: () {
        final tid = threadRootId;
        if (tid != null) {
          context.goNamed(
            Routes.roomThread,
            pathParameters: {
              RouteParams.roomId: item.roomId,
              RouteParams.eventId: tid,
            },
          );
        } else {
          context.goNamed(
            Routes.room,
            pathParameters: {RouteParams.roomId: item.roomId},
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unread indicator
            if (!item.isRead)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 6),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              )
            else
              const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      if (item.isMention) ...[
                        Icon(KIcons.alternateEmailRounded,
                            size: 12, color: cs.primary,),
                        const SizedBox(width: 2),
                        Text(
                          threadRootId != null
                              ? InboxText.mentionInThread
                              : InboxText.mention,
                          style: tt.labelSmall?.copyWith(
                            color: cs.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        formatRelativeTimestamp(ts),
                        style: tt.bodySmall?.copyWith(
                          fontSize: 11,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
