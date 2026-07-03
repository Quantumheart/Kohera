import 'package:flutter/material.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/utils/confirm_dialog.dart';
import 'package:kohera/features/rooms/models/kohera_room_summary.dart';
import 'package:kohera/shared/widgets/room_avatar.dart';
import 'package:provider/provider.dart';

/// Shared dialog for accepting or declining a room/space invitation.
///
/// SDK-free: display data comes from [KoheraRoomSummary] and the accept/decline
/// actions are delegated to callbacks supplied by the parent, which retains
/// `Room` access.
///
/// Returns `true` if accepted, `false` if declined, `null` if dismissed.
class InviteDialog extends StatefulWidget {
  const InviteDialog({
    required this.roomId,
    required this.summary,
    required this.onAccept,
    required this.onDecline,
    this.inviterName,
    super.key,
  });

  /// The Matrix room/space ID being invited to.
  final String roomId;

  /// Pre-computed display fields (displayname, avatar, isSpace, …).
  final KoheraRoomSummary summary;

  /// Resolved display name of the inviter, or `null` if unknown.
  final String? inviterName;

  /// Joins the room/space. Throwing errors are caught and shown inline.
  final Future<void> Function() onAccept;

  /// Leaves (declines) the room/space. Throwing errors are caught and shown.
  final Future<void> Function() onDecline;

  /// Show the invite dialog and return the user's decision.
  static Future<bool?> show(
    BuildContext context, {
    required String roomId,
    required KoheraRoomSummary summary,
    required Future<void> Function() onAccept,
    required Future<void> Function() onDecline,
    String? inviterName,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => InviteDialog(
        roomId: roomId,
        summary: summary,
        inviterName: inviterName,
        onAccept: onAccept,
        onDecline: onDecline,
      ),
    );
  }

  @override
  State<InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<InviteDialog> {
  bool _accepting = false;
  bool _declining = false;
  String? _error;

  Future<void> _accept() async {
    setState(() {
      _accepting = true;
      _error = null;
    });
    try {
      await widget.onAccept();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('[Kohera] Accept invite failed: $e');
      if (mounted) {
        setState(() {
          _accepting = false;
          _error = MatrixService.friendlyAuthError(e);
        });
      }
    }
  }

  Future<void> _decline() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Decline invite',
      message: 'Decline invite to ${widget.summary.displayname}?',
      confirmLabel: 'Decline',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _declining = true;
      _error = null;
    });
    try {
      await widget.onDecline();
      if (mounted) Navigator.pop(context, false);
    } catch (e) {
      debugPrint('[Kohera] Decline invite failed: $e');
      if (mounted) {
        setState(() {
          _declining = false;
          _error = MatrixService.friendlyAuthError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final name = widget.summary.displayname;
    final inviter = widget.inviterName;
    final inFlight = _accepting || _declining;

    return AlertDialog(
      title: Text(widget.summary.isSpace ? 'Space invite' : 'Room invite'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RoomAvatarWidget(
              avatarUrl: widget.summary.avatarUrl,
              displayname: widget.summary.displayname,
              avatarResolver: context.read<MatrixService>().avatarResolver,
              size: 56,
            ),
            const SizedBox(height: 12),
            Text(name, style: tt.titleMedium),
            if (inviter != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Invited by $inviter',
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: cs.error, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: inFlight ? null : _decline,
          child: _declining
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('Decline', style: TextStyle(color: cs.error)),
        ),
        FilledButton(
          onPressed: inFlight ? null : _accept,
          child: _accepting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.onPrimary,
                  ),
                )
              : const Text('Accept'),
        ),
      ],
    );
  }
}
