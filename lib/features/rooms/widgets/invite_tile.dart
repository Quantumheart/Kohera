import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/utils/confirm_dialog.dart';
import 'package:kohera/shared/models/kohera_room_summary.dart';
import 'package:kohera/shared/widgets/room_avatar.dart';
import 'package:provider/provider.dart';

// ── Invite tile ─────────────────────────────────────────────
class InviteTile extends StatefulWidget {
  const InviteTile({
    required this.summary,
    this.inviterName,
    this.onJoin,
    this.onDecline,
    super.key,
  });

  final KoheraRoomSummary summary;
  final String? inviterName;

  /// Called when the user accepts the invite. The caller handles room.join().
  final Future<void> Function()? onJoin;

  /// Called when the user declines the invite. The caller handles room.leave().
  final Future<void> Function()? onDecline;

  @override
  State<InviteTile> createState() => _InviteTileState();
}

class _InviteTileState extends State<InviteTile> {
  bool _isJoining = false;
  bool _isDeclining = false;

  bool get _inFlight => _isJoining || _isDeclining;

  Future<void> _accept() async {
    if (_inFlight) return;
    final matrix = context.read<MatrixService>();
    setState(() => _isJoining = true);
    try {
      if (widget.onJoin != null) {
        await widget.onJoin!();
      } else {
        // Fallback: join via the client
        final room = matrix.client.getRoomById(widget.summary.roomId);
        if (room != null) await room.join();
      }
    } catch (e) {
      debugPrint('[Kohera] Accept invite failed: $e');
      if (mounted) context.showSnack(MatrixService.friendlyAuthError(e));
      if (mounted) setState(() => _isJoining = false);
      return;
    }
    // Join succeeded — wait briefly for the sync so the room appears as joined.
    try {
      await matrix.client.onSync.stream.first
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Timeout is fine — the join already succeeded server-side.
    }
    if (mounted) {
      context.goNamed(
        Routes.room,
        pathParameters: {RouteParams.roomId: widget.summary.roomId},
      );
      setState(() => _isJoining = false);
    }
  }

  Future<void> _decline() async {
    if (_inFlight) return;
    final confirmed = await confirmDialog(
      context,
      title: 'Decline invite',
      message: 'Decline invite to ${widget.summary.displayname}?',
      confirmLabel: 'Decline',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isDeclining = true);
    try {
      if (widget.onDecline != null) {
        await widget.onDecline!();
      } else {
        final matrix = context.read<MatrixService>();
        final room = matrix.client.getRoomById(widget.summary.roomId);
        if (room != null) await room.leave();
      }
    } catch (e) {
      debugPrint('[Kohera] Decline invite failed: $e');
      if (mounted) context.showSnack(MatrixService.friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _isDeclining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final inviter = widget.inviterName;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: cs.tertiaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
        child: InkWell(
          borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
          mouseCursor: SystemMouseCursors.click,
          onTap: _inFlight ? null : _accept,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Avatar
                if (_isJoining)
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  )
                else
                  RoomAvatarWidget(
                    avatarUrl: widget.summary.avatarUrl,
                    displayname: widget.summary.displayname,
                    avatarResolver:
                        context.read<MatrixService>().avatarResolver,
                    size: 48,
                  ),

                const SizedBox(width: 12),

                // Name + invite subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.summary.displayname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        inviter != null
                            ? 'Invited by $inviter'
                            : 'Pending invite',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onTertiaryContainer.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Decline button
                if (_isDeclining)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: cs.error),
                    tooltip: 'Decline invite',
                    onPressed: _inFlight ? null : _decline,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
