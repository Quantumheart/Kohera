import 'package:flutter/material.dart';
import 'package:kohera/core/utils/time_format.dart';
import 'package:kohera/features/chat/widgets/density_metrics.dart';
import 'package:matrix/matrix.dart';

class MessageBubbleTimestamp extends StatelessWidget {
  const MessageBubbleTimestamp({
    required this.event,
    required this.isMe,
    required this.isPinned,
    required this.isEdited,
    required this.metrics,
    super.key,
  });

  final Event event;
  final bool isMe;
  final bool isPinned;
  final bool isEdited;
  final DensityMetrics metrics;

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
            formatMessageTime(event.originServerTs),
            style: tt.bodyMedium?.copyWith(
              fontSize: metrics.timestampFontSize,
              color: mutedColor,
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 4),
            Icon(
              event.status.isSent
                  ? Icons.done_all_rounded
                  : Icons.done_rounded,
              size: metrics.statusIconSize,
              color: cs.onPrimary.withValues(alpha: 0.6),
            ),
          ],
        ],
      ),
    );
  }
}
