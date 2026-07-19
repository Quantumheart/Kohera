import 'package:flutter/material.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:matrix/matrix.dart';

/// Shows a dialog collecting a required reason for reporting content.
///
/// Returns the trimmed reason when submitted, or `null` when cancelled.
/// Submit is disabled until the reason is non-empty.
Future<String?> showReportContentDialog(BuildContext context) {
  return showDialog<String?>(
    context: context,
    builder: (ctx) => const _ReportContentDialog(),
  );
}

/// Reports a room (or space) by its most recent event to the homeserver.
///
/// The Matrix `/report` endpoint is per-event; there is no room-level
/// report, so the room's [Room.lastEvent] is used as the representative
/// event. Prompts for a reason via [showReportContentDialog] and surfaces
/// success/failure via snackbar.
Future<void> reportRoomContent(
  BuildContext context,
  Client client,
  String roomId,
) async {
  final room = client.getRoomById(roomId);
  final eventId = room?.lastEvent?.eventId;
  if (room == null || eventId == null) {
    if (context.mounted) {
      context.showSnack('No message available to report');
    }
    return;
  }
  final reason = await showReportContentDialog(context);
  if (reason == null || reason.isEmpty || !context.mounted) return;
  try {
    await client.reportEvent(room.id, eventId, reason: reason);
    if (context.mounted) context.showSnack('Reported to homeserver');
  } catch (e) {
    debugPrint('[Kohera] Report room failed: $e');
    if (context.mounted) {
      context.showSnack('Failed to report: ${MatrixService.friendlyAuthError(e)}');
    }
  }
}

class _ReportContentDialog extends StatefulWidget {
  const _ReportContentDialog();

  @override
  State<_ReportContentDialog> createState() => _ReportContentDialogState();
}

class _ReportContentDialogState extends State<_ReportContentDialog> {
  final _controller = TextEditingController();
  bool _canSubmit = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final canSubmit = value.trim().isNotEmpty;
    if (canSubmit != _canSubmit) setState(() => _canSubmit = canSubmit);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Report content?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Report this content to your homeserver. Moderators will review it.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            textInputAction: TextInputAction.done,
            maxLength: 240,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'Why are you reporting this?',
              border: OutlineInputBorder(),
            ),
            onChanged: _onChanged,
            onSubmitted: _canSubmit
                ? (_) => Navigator.pop(context, _controller.text.trim())
                : null,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: cs.error,
            foregroundColor: cs.onError,
          ),
          onPressed: _canSubmit
              ? () => Navigator.pop(context, _controller.text.trim())
              : null,
          child: const Text('Report'),
        ),
      ],
    );
  }
}
