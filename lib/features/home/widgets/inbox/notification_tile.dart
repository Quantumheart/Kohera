import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/utils/reply_fallback.dart';
import 'package:kohera/core/utils/time_format.dart';
import 'package:kohera/features/notifications/models/notification_constants.dart';
import 'package:kohera/features/notifications/services/inbox_controller.dart';
import 'package:matrix/matrix.dart' as matrix_sdk;
import 'package:provider/provider.dart';

class NotificationTile extends StatelessWidget {
  const NotificationTile({
    required this.notification,
    required this.client,
    required this.threadRootId,
    super.key,
  });

  final matrix_sdk.Notification notification;
  final matrix_sdk.Client client;
  final String? threadRootId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final event = notification.event;

    final senderId = event.senderId;
    final room = client.getRoomById(notification.roomId);
    final senderName =
        room?.unsafeGetUserFromMemoryOrFallback(senderId).calcDisplayname() ??
            senderId;

    final controller = context.read<InboxController>();
    final body = _extractBody(context, event);
    final ts = DateTime.fromMillisecondsSinceEpoch(notification.ts);
    final isMention = controller.isMention(notification);

    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      canRequestFocus: false,
      onTap: () {
        final tid = threadRootId;
        if (tid != null) {
          context.goNamed(
            Routes.roomThread,
            pathParameters: {
              RouteParams.roomId: notification.roomId,
              RouteParams.eventId: tid,
            },
          );
        } else {
          context.goNamed(
            Routes.room,
            pathParameters: {RouteParams.roomId: notification.roomId},
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unread indicator
            if (!notification.read)
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
                          senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      if (isMention) ...[
                        Icon(Icons.alternate_email_rounded,
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

  String _extractBody(BuildContext context, matrix_sdk.MatrixEvent event) {
    final controller = context.read<InboxController>();
    final content =
        controller.decryptedContentFor(event.eventId) ?? event.content;
    final msgtype = content['msgtype'];

    if (msgtype == matrix_sdk.MessageTypes.Image) return InboxText.mediaImage;
    if (msgtype == matrix_sdk.MessageTypes.Video) return InboxText.mediaVideo;
    if (msgtype == matrix_sdk.MessageTypes.Audio) return InboxText.mediaAudio;
    if (msgtype == matrix_sdk.MessageTypes.File) return InboxText.mediaFile;

    final body = content['body'];
    if (body is String) return stripReplyFallback(body);

    return '';
  }
}
