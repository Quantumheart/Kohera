import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class ThreadIndicatorChip extends StatelessWidget {
  const ThreadIndicatorChip({
    required this.event,
    required this.timeline,
    required this.isMe,
    required this.onTap,
    super.key,
  });

  final Event event;
  final Timeline timeline;
  final bool isMe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final children = event.aggregatedEvents(timeline, RelationshipTypes.thread);
    if (children.isEmpty) return const SizedBox.shrink();
    final count = children.length;
    final label = count == 1 ? '1 reply' : '$count replies';

    return Padding(
      padding: EdgeInsets.only(
        top: 4,
        left: isMe ? 0 : 4,
        right: isMe ? 4 : 0,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
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
            ],
          ),
        ),
      ),
      ),
    );
  }
}
