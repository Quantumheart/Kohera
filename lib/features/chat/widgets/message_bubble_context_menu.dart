import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kohera/core/utils/reply_fallback.dart';
import 'package:kohera/shared/widgets/popup_menu_item_row.dart';
import 'package:matrix/matrix.dart';

Future<void> showMessageContextMenu(
  BuildContext context, {
  required Event event,
  required bool isMe,
  required bool isPinned,
  required Timeline? timeline,
  required Offset position,
  VoidCallback? onReply,
  VoidCallback? onEdit,
  VoidCallback? onReact,
  VoidCallback? onPin,
  VoidCallback? onDelete,
  VoidCallback? onReplyInThread,
  VoidCallback? onForward,
}) async {
  final cs = Theme.of(context).colorScheme;
  final isFailed = event.status.isError;
  final items = <PopupMenuItem<String>>[
    if (isFailed) ...[
      menuItemRow(Icons.refresh_rounded, 'Retry sending', 'outbox_retry'),
      menuItemRow(
        Icons.delete_outline_rounded,
        'Discard message',
        'outbox_discard',
        color: cs.error,
      ),
    ] else ...[
      if (onReply != null) menuItemRow(Icons.reply_rounded, 'Reply', 'reply'),
      if (onReplyInThread != null)
        menuItemRow(Icons.forum_outlined, 'Reply in thread', 'reply_in_thread'),
      if (onEdit != null) menuItemRow(Icons.edit_rounded, 'Edit', 'edit'),
      if (onReact != null)
        menuItemRow(Icons.add_reaction_outlined, 'React', 'react'),
      if (!event.redacted) menuItemRow(Icons.copy_rounded, 'Copy', 'copy'),
      if (onForward != null)
        menuItemRow(Icons.forward_rounded, 'Forward', 'forward'),
      if (onPin != null)
        menuItemRow(
          isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
          isPinned ? 'Unpin' : 'Pin',
          'pin',
        ),
      if (onDelete != null)
        menuItemRow(
          Icons.delete_outline_rounded,
          isMe ? 'Delete' : 'Remove',
          'delete',
          color: cs.error,
        ),
    ],
  ];
  if (items.isEmpty) return;
  final value = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
        position.dx, position.dy, position.dx, position.dy,),
    color: cs.surfaceContainer,
    items: items,
  );
  if (!context.mounted) return;
  if (value == 'outbox_retry') {
    try {
      await event.sendAgain();
    } catch (e) {
      debugPrint('[Kohera] outbox: retry from menu failed: $e');
    }
    return;
  }
  if (value == 'outbox_discard') {
    try {
      await event.cancelSend();
    } catch (e) {
      debugPrint('[Kohera] outbox: discard from menu failed: $e');
    }
    return;
  }
  if (value == 'reply') onReply?.call();
  if (value == 'forward') onForward?.call();
  if (value == 'reply_in_thread') onReplyInThread?.call();
  if (value == 'react') onReact?.call();
  if (value == 'edit') onEdit?.call();
  if (value == 'pin') onPin?.call();
  if (value == 'copy') {
    final displayEvent =
        timeline != null ? event.getDisplayEvent(timeline) : event;
    await Clipboard.setData(
        ClipboardData(text: stripReplyFallback(displayEvent.body)),);
  }
  if (value == 'delete') onDelete?.call();
}
