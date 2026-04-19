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
}) async {
  final cs = Theme.of(context).colorScheme;
  final items = <PopupMenuItem<String>>[
    if (onReply != null) _menuItem(Icons.reply_rounded, 'Reply', 'reply'),
    if (onEdit != null) _menuItem(Icons.edit_rounded, 'Edit', 'edit'),
    if (onReact != null)
      _menuItem(Icons.add_reaction_outlined, 'React', 'react'),
    if (!event.redacted) _menuItem(Icons.copy_rounded, 'Copy', 'copy'),
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
  if (value == 'reply') onReply?.call();
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
