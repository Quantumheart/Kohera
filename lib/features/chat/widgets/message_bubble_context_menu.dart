import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kohera/shared/widgets/popup_menu_item_row.dart';

Future<void> showMessageContextMenu(
  BuildContext context, {
  required bool isMe,
  required bool isPinned,
  required bool isFailed,
  required bool isRedacted,
  required String copyableBody,
  required Offset position,
  VoidCallback? onReply,
  VoidCallback? onEdit,
  VoidCallback? onReact,
  VoidCallback? onPin,
  VoidCallback? onDelete,
  VoidCallback? onReplyInThread,
  VoidCallback? onForward,
  VoidCallback? onRetrySend,
  VoidCallback? onDiscardSend,
  VoidCallback? onIgnoreSender,
}) async {
  final cs = Theme.of(context).colorScheme;
  final items = <PopupMenuItem<String>>[
    if (isFailed) ...[
      if (onRetrySend != null)
        menuItemRow(Icons.refresh_rounded, 'Retry sending', 'outbox_retry'),
      if (onDiscardSend != null)
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
      if (!isRedacted) menuItemRow(Icons.copy_rounded, 'Copy', 'copy'),
      if (onForward != null)
        menuItemRow(Icons.forward_rounded, 'Forward', 'forward'),
      if (onPin != null)
        menuItemRow(
          isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
          isPinned ? 'Unpin' : 'Pin',
          'pin',
        ),
      if (onIgnoreSender != null)
        menuItemRow(
          Icons.do_not_disturb_on_outlined,
          'Ignore user',
          'ignore_sender',
          color: cs.error,
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
    onRetrySend?.call();
    return;
  }
  if (value == 'outbox_discard') {
    onDiscardSend?.call();
    return;
  }
  if (value == 'reply') onReply?.call();
  if (value == 'forward') onForward?.call();
  if (value == 'reply_in_thread') onReplyInThread?.call();
  if (value == 'react') onReact?.call();
  if (value == 'edit') onEdit?.call();
  if (value == 'pin') onPin?.call();
  if (value == 'ignore_sender') onIgnoreSender?.call();
  if (value == 'copy') {
    await Clipboard.setData(ClipboardData(text: copyableBody));
  }
  if (value == 'delete') onDelete?.call();
}
