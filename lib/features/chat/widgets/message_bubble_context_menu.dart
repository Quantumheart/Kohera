import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kohera/core/theme/k_icons.dart';
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
}) async {
  final cs = Theme.of(context).colorScheme;
  final items = <PopupMenuItem<String>>[
    if (isFailed) ...[
      if (onRetrySend != null)
        menuItemRow(KIcons.refreshRounded, 'Retry sending', 'outbox_retry'),
      if (onDiscardSend != null)
        menuItemRow(
          KIcons.deleteOutlineRounded,
          'Discard message',
          'outbox_discard',
          color: cs.error,
        ),
    ] else ...[
      if (onReply != null) menuItemRow(KIcons.replyRounded, 'Reply', 'reply'),
      if (onReplyInThread != null)
        menuItemRow(KIcons.forumOutlined, 'Reply in thread', 'reply_in_thread'),
      if (onEdit != null) menuItemRow(KIcons.editRounded, 'Edit', 'edit'),
      if (onReact != null)
        menuItemRow(KIcons.addReactionOutlined, 'React', 'react'),
      if (!isRedacted) menuItemRow(KIcons.copyRounded, 'Copy', 'copy'),
      if (onForward != null)
        menuItemRow(KIcons.forwardRounded, 'Forward', 'forward'),
      if (onPin != null)
        menuItemRow(
          isPinned ? KIcons.pushPinRounded : KIcons.pushPinOutlined,
          isPinned ? 'Unpin' : 'Pin',
          'pin',
        ),
      if (onDelete != null)
        menuItemRow(
          KIcons.deleteOutlineRounded,
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
  if (value == 'copy') {
    await Clipboard.setData(ClipboardData(text: copyableBody));
  }
  if (value == 'delete') onDelete?.call();
}
