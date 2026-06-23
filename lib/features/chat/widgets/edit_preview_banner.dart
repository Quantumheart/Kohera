import 'package:flutter/material.dart';
import 'package:kohera/features/chat/widgets/compose_preview_banner.dart';
import 'package:matrix/matrix.dart';

class EditPreviewBanner extends StatelessWidget {
  const EditPreviewBanner({
    required this.event, required this.onCancel, super.key,
  });

  final Event event;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ComposePreviewBanner(
      icon: Icons.edit_rounded,
      accentColor: Theme.of(context).colorScheme.primary,
      title: 'Editing',
      event: event,
      onCancel: onCancel,
    );
  }
}
