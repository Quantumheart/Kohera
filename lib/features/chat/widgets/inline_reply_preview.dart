import 'package:flutter/material.dart';

import 'package:kohera/core/utils/sender_color.dart';
import 'package:kohera/features/chat/models/kohera_reply_preview.dart';

// coverage:ignore-start

// ── Inline reply preview ──────────────────────────────────────

class InlineReplyPreview extends StatelessWidget {
  const InlineReplyPreview({
    required this.preview,
    required this.isMe,
    this.onTap,
    super.key,
  });

  final KoheraReplyPreview? preview;
  final bool isMe;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final parentAvailable = preview != null;
    final color = parentAvailable
        ? senderColor(preview!.parentSenderId ?? '', cs)
        : cs.onSurfaceVariant;

    return GestureDetector(
      onTap: parentAvailable ? onTap : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.only(left: 8, right: 4, top: 4, bottom: 4),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 2)),
          color: isMe
              ? cs.onPrimary.withValues(alpha: 0.12)
              : cs.onSurface.withValues(alpha: 0.06),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(4),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: parentAvailable
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preview!.parentSenderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  Text(
                    preview!.parentBody,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      color: isMe
                          ? cs.onPrimary.withValues(alpha: 0.7)
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              )
            : Text(
                'Message not available',
                style: tt.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: isMe
                      ? cs.onPrimary.withValues(alpha: 0.5)
                      : cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
      ),
    );
  }
}
// coverage:ignore-end
