import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kohera/core/utils/reply_fallback.dart';
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
      _menuItem(Icons.refresh_rounded, 'Retry sending', 'outbox_retry'),
      _menuItem(
        Icons.delete_outline_rounded,
        'Discard message',
        'outbox_discard',
        color: cs.error,
      ),
    ] else ...[
      if (onReply != null) _menuItem(Icons.reply_rounded, 'Reply', 'reply'),
      if (onReplyInThread != null)
        _menuItem(Icons.forum_outlined, 'Reply in thread', 'reply_in_thread'),
      if (onEdit != null) _menuItem(Icons.edit_rounded, 'Edit', 'edit'),
      if (onReact != null)
        _menuItem(Icons.add_reaction_outlined, 'React', 'react'),
      if (!event.redacted) _menuItem(Icons.copy_rounded, 'Copy', 'copy'),
      if (onForward != null)
        _menuItem(Icons.forward_rounded, 'Forward', 'forward'),
      if (onPin != null)
        _menuItem(
          isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
          isPinned ? 'Unpin' : 'Pin',
          'pin',
        ),
      if (onDelete != null)
        _menuItem(
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
  if (value == 'forward') onForward?.call();
}

PopupMenuItem<String> _menuItem(
  IconData icon,
  String label,
  String value, {
  Color? color,
}) {
  return PopupMenuItem<String>(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(label, style: color == null ? null : TextStyle(color: color)),
      ],
    ),
  );
}
