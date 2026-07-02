import 'package:flutter/material.dart';
import 'package:kohera/core/utils/time_format.dart';
import 'package:kohera/features/chat/models/kohera_message_status.dart';
import 'package:kohera/features/chat/widgets/density_metrics.dart';
import 'package:kohera/features/chat/widgets/message_bubble_outbox_status.dart';

class MessageBubbleTimestamp extends StatelessWidget {
  const MessageBubbleTimestamp({
    required this.timestamp,
    required this.isMe,
    required this.isPinned,
    required this.isEdited,
    required this.metrics,
    required this.eventId,
    required this.transactionId,
    required this.status,
    super.key,
  });

  final DateTime timestamp;
  final bool isMe;
  final bool isPinned;
  final bool isEdited;
  final DensityMetrics metrics;
  final String eventId;
  final String? transactionId;
  final KoheraMessageStatus status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final mutedColor = isMe
        ? cs.onPrimary.withValues(alpha: 0.6)
        : cs.onSurfaceVariant.withValues(alpha: 0.5);

    return Padding(
      padding: EdgeInsets.only(top: metrics.timestampTopPad),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPinned)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                Icons.push_pin_rounded,
                size: metrics.timestampFontSize + 2,
                color: mutedColor,
              ),
            ),
          if (isEdited)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                '(edited)',
                style: tt.bodyMedium?.copyWith(
                  fontSize: metrics.timestampFontSize,
                  color: mutedColor,
                ),
              ),
            ),
          Text(
            formatMessageTime(timestamp),
            style: tt.bodyMedium?.copyWith(
              fontSize: metrics.timestampFontSize,
              color: mutedColor,
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 4),
            MessageBubbleOutboxStatus(
              eventId: eventId,
              transactionId: transactionId,
              status: status,
              metrics: metrics,
            ),
          ],
        ],
      ),
    );
  }
}
