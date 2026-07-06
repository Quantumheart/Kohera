import 'package:flutter/material.dart';
import 'package:kohera/core/utils/reply_fallback.dart';
import 'package:kohera/features/chat/services/thread_summary.dart';

class ThreadListTile extends StatelessWidget {
  const ThreadListTile({
    required this.summary,
    required this.onTap,
    super.key,
  });

  final ThreadSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final root = summary.root;
    final lastReply = summary.lastReply;
    final preview = root.redacted
        ? '[redacted]'
        : stripReplyFallback(root.body).trim();
    final replySender =
        lastReply?.senderFromMemoryOrFallback.displayName ??
            lastReply?.senderId ??
            '';
    final replyText = lastReply == null
        ? ''
        : (lastReply.redacted
            ? '[redacted]'
            : stripReplyFallback(lastReply.body).trim());
    final hasUnread = summary.unreadCount > 0;

    final previewLabel = preview.isEmpty ? 'Thread' : preview;
    final semanticsLabel = hasUnread
        ? 'Open thread: $previewLabel, ${summary.unreadCount} unread'
        : 'Open thread: $previewLabel';

    return Semantics(
      button: true,
      label: semanticsLabel,
      child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.forum_outlined, color: cs.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            preview.isEmpty ? 'Thread' : preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodyMedium?.copyWith(
                              fontWeight: hasUnread
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(summary.lastActivity),
                          style: tt.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    if (lastReply != null)
                      Text(
                        '$replySender: $replyText',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          summary.replyCount == 1
                              ? '1 reply'
                              : '${summary.replyCount} replies',
                          style: tt.labelSmall?.copyWith(color: cs.primary),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1,),
                            decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
                            ),
                            child: Text(
                              summary.unreadCount > 99
                                  ? '99+'
                                  : '${summary.unreadCount}',
                              style: tt.labelSmall?.copyWith(
                                color: cs.onPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

String _formatTime(DateTime ts) {
  final now = DateTime.now();
  final local = ts.toLocal();
  final sameDay = now.year == local.year &&
      now.month == local.month &&
      now.day == local.day;
  if (sameDay) {
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
  final mm = local.month.toString().padLeft(2, '0');
  final dd = local.day.toString().padLeft(2, '0');
  return '$mm-$dd';
}
