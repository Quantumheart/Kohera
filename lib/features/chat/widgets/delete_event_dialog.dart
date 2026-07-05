import 'package:flutter/material.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/core/services/matrix_service.dart';

/// Shows a confirmation dialog and calls [onRedact] if the user confirms.
///
/// [isMe] controls the dialog wording ("Delete" vs "Remove"). [onRedact]
/// performs the actual redaction — the caller has SDK access and calls
/// `room.redactEvent(eventId)`. Errors from [onRedact] are caught and shown
/// as a snackbar.
Future<void> confirmAndDeleteEvent(
  BuildContext context, {
  required bool isMe,
  required Future<void> Function() onRedact,
}) async {
  final title = isMe ? 'Delete message?' : 'Remove message?';
  final body = isMe
      ? 'This message will be permanently deleted for everyone.'
      : 'This message will be permanently removed from the room.';

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: Text(isMe ? 'Delete' : 'Remove'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  if (!context.mounted) return;

  try {
    await onRedact();
  } catch (e) {
    if (context.mounted) {
      context.showSnack(
        'Failed to delete: ${MatrixService.friendlyAuthError(e)}',
      );
    }
  }
}
