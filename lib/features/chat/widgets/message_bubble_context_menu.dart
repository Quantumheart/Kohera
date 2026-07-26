import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kohera/shared/widgets/popup_menu_item_row.dart';

/// Vertical offset of the secondary "More…" menu from the primary anchor,
/// so the second tier does not reopen over the same tap point.
const double _secondaryMenuOffset = 48;

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
  VoidCallback? onReport,
}) async {
  final cs = Theme.of(context).colorScheme;

  // ── Failed branch: Retry / Discard only ──────────────────────
  if (isFailed) {
    final failedItems = <PopupMenuItem<String>>[
      if (onRetrySend != null)
        menuItemRow(Icons.refresh_rounded, 'Retry sending', 'outbox_retry'),
      if (onDiscardSend != null)
        menuItemRow(
          Icons.delete_outline_rounded,
          'Discard message',
          'outbox_discard',
          color: cs.error,
        ),
    ];
    if (failedItems.isEmpty) return;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: cs.surfaceContainer,
      items: failedItems,
    );
    if (!context.mounted) return;
    if (value == 'outbox_retry') onRetrySend?.call();
    if (value == 'outbox_discard') onDiscardSend?.call();
    return;
  }

  // ── Primary tier ─────────────────────────────────────────────
  final hasSecondary = [
    onReplyInThread,
    onForward,
    onPin,
    onIgnoreSender,
    onReport,
  ].any((c) => c != null);

  final primaryItems = <PopupMenuItem<String>>[
    if (onReply != null) menuItemRow(Icons.reply_rounded, 'Reply', 'reply'),
    if (onReact != null)
      menuItemRow(Icons.add_reaction_outlined, 'React', 'react'),
    if (onEdit != null) menuItemRow(Icons.edit_rounded, 'Edit', 'edit'),
    if (!isRedacted) menuItemRow(Icons.copy_rounded, 'Copy', 'copy'),
    if (onDelete != null)
      menuItemRow(
        Icons.delete_outline_rounded,
        isMe ? 'Delete' : 'Remove',
        'delete',
        color: cs.error,
      ),
    if (hasSecondary) menuItemRow(Icons.more_horiz_rounded, 'More…', 'more'),
  ];
  if (primaryItems.isEmpty) return;

  final primary = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx,
      position.dy,
    ),
    color: cs.surfaceContainer,
    items: primaryItems,
  );
  if (!context.mounted) return;
  if (primary == 'more') {
    final secondaryItems = <PopupMenuItem<String>>[
      if (onReplyInThread != null)
        menuItemRow(Icons.forum_outlined, 'Reply in thread', 'reply_in_thread'),
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
      if (onReport != null)
        menuItemRow(
          Icons.flag_outlined,
          'Report',
          'report',
          color: cs.error,
        ),
    ];
    final secondary = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + _secondaryMenuOffset,
        position.dx,
        position.dy + _secondaryMenuOffset,
      ),
      color: cs.surfaceContainer,
      items: secondaryItems,
    );
    if (!context.mounted) return;
    await _dispatchMenuValue(
      secondary,
      onReply: onReply,
      onEdit: onEdit,
      onReact: onReact,
      onPin: onPin,
      onDelete: onDelete,
      onReplyInThread: onReplyInThread,
      onForward: onForward,
      onIgnoreSender: onIgnoreSender,
      onReport: onReport,
      copyableBody: copyableBody,
    );
    return;
  }

  await _dispatchMenuValue(
    primary,
    onReply: onReply,
    onEdit: onEdit,
    onReact: onReact,
    onPin: onPin,
    onDelete: onDelete,
    onReplyInThread: onReplyInThread,
    onForward: onForward,
    onIgnoreSender: onIgnoreSender,
    onReport: onReport,
    copyableBody: copyableBody,
  );
}

Future<void> _dispatchMenuValue(
  String? value, {
  required String copyableBody,
  VoidCallback? onReply,
  VoidCallback? onEdit,
  VoidCallback? onReact,
  VoidCallback? onPin,
  VoidCallback? onDelete,
  VoidCallback? onReplyInThread,
  VoidCallback? onForward,
  VoidCallback? onIgnoreSender,
  VoidCallback? onReport,
}) async {
  switch (value) {
    case 'reply':
      onReply?.call();
    case 'forward':
      onForward?.call();
    case 'reply_in_thread':
      onReplyInThread?.call();
    case 'react':
      onReact?.call();
    case 'edit':
      onEdit?.call();
    case 'pin':
      onPin?.call();
    case 'ignore_sender':
      onIgnoreSender?.call();
    case 'report':
      onReport?.call();
    case 'copy':
      await Clipboard.setData(ClipboardData(text: copyableBody));
    case 'delete':
      onDelete?.call();
    default:
      break;
  }
}
