import 'package:flutter/material.dart';
import 'package:kohera/core/utils/sender_color.dart';
import 'package:kohera/features/chat/widgets/compose_preview_banner.dart';
import 'package:matrix/matrix.dart';

class ReplyPreviewBanner extends StatelessWidget {
  const ReplyPreviewBanner({
    required this.event, required this.onCancel, super.key,
  });

  final Event event;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ComposePreviewBanner(
      icon: Icons.reply_rounded,
      accentColor: senderColor(event.senderId, cs),
      title: event.senderFromMemoryOrFallback.displayName ?? event.senderId,
      event: event,
      onCancel: onCancel,
    );
  }
}
