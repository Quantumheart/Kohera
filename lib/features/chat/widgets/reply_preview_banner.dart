import 'package:flutter/material.dart';

import 'package:kohera/core/utils/sender_color.dart';
import 'package:kohera/features/chat/models/kohera_reply_preview.dart';
import 'package:kohera/features/chat/widgets/compose_preview_banner.dart';

class ReplyPreviewBanner extends StatelessWidget {
  const ReplyPreviewBanner({
    required this.preview, required this.onCancel, super.key,
  });

  final KoheraReplyPreview preview;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ComposePreviewBanner(
      icon: Icons.reply_rounded,
      accentColor: senderColor(preview.parentSenderId ?? '', cs),
      title: preview.parentSenderName,
      preview: preview,
      onCancel: onCancel,
    );
  }
}
