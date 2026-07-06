import 'package:flutter/material.dart';

class ThreadIndicatorChip extends StatelessWidget {
  const ThreadIndicatorChip({
    required this.replyCount,
    required this.isMe,
    required this.onTap,
    this.unreadCount = 0,
    super.key,
  });

  final int replyCount;
  final bool isMe;
  final VoidCallback onTap;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final count = replyCount;
    final label = count == 1 ? '1 reply' : '$count replies';

    return Padding(
      padding: EdgeInsets.only(
        top: 4,
        left: isMe ? 0 : 4,
        right: isMe ? 4 : 0,
      ),
      child: Semantics(
        button: true,
        label: unreadCount > 0
            ? 'View thread, $label, $unreadCount unread'
            : 'View thread, $label',
        child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: tt.labelSmall?.copyWith(color: cs.primary),
              ),
              const SizedBox(width: 4),
              Text(
                'View thread',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              if (unreadCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      ),
      ),
    );
  }
}
