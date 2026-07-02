import 'package:flutter/material.dart';
import 'package:kohera/core/utils/sender_color.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/widgets/density_metrics.dart';
import 'package:kohera/features/chat/widgets/message_bubble_body.dart';
import 'package:kohera/features/chat/widgets/message_bubble_link_preview.dart';
import 'package:kohera/features/chat/widgets/message_bubble_timestamp.dart';

const _msgtypeText = 'm.text';
const _msgtypeNotice = 'm.notice';

class MessageBubbleContent extends StatelessWidget {
  const MessageBubbleContent({
    required this.message,
    required this.isMe,
    required this.isFirst,
    required this.isPinned,
    required this.metrics,
    required this.htmlBuilder,
    this.replyPreview,
    this.mediaBody,
    super.key,
  });

  final KoheraMessageDisplay message;
  final bool isMe;
  final bool isFirst;
  final bool isPinned;
  final DensityMetrics metrics;
  final HtmlBodyBuilder htmlBuilder;
  final Widget? replyPreview;
  final Widget? mediaBody;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final isTextMessage = !message.isRedacted &&
        (message.messageType == _msgtypeText ||
            message.messageType == _msgtypeNotice);

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.replyEventId != null && replyPreview != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: replyPreview,
            ),
          if (!isMe && isFirst)
            Padding(
              padding: EdgeInsets.only(bottom: metrics.senderNameBottomPad),
              child: Text(
                message.senderName,
                style: tt.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: metrics.senderNameFontSize,
                  color: senderColor(message.senderId, cs),
                ),
              ),
            ),
          if (mediaBody != null)
            mediaBody!
          else
            MessageBubbleBody(
              message: message,
              isMe: isMe,
              metrics: metrics,
              htmlBuilder: htmlBuilder,
            ),
          if (isTextMessage)
            MessageBubbleLinkPreview(bodyText: message.body, isMe: isMe),
          MessageBubbleTimestamp(
            timestamp: message.timestamp,
            isMe: isMe,
            isPinned: isPinned,
            isEdited: message.isEdited,
            metrics: metrics,
            eventId: message.eventId,
            transactionId: message.transactionId,
            status: message.status,
          ),
        ],
      ),
    );
  }
}
