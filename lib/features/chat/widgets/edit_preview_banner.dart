import 'package:flutter/material.dart';

import 'package:kohera/features/chat/models/kohera_reply_preview.dart';
import 'package:kohera/features/chat/widgets/compose_preview_banner.dart';

class EditPreviewBanner extends StatelessWidget {
  const EditPreviewBanner({
    required this.preview, required this.onCancel, super.key,
  });

  final KoheraReplyPreview preview;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ComposePreviewBanner(
      icon: Icons.edit_rounded,
      accentColor: Theme.of(context).colorScheme.primary,
      title: 'Editing',
      preview: preview,
      onCancel: onCancel,
    );
  }
}
