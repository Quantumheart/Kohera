import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/presence_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/core/utils/confirm_dialog.dart';
import 'package:kohera/features/rooms/models/room_role.dart';
import 'package:kohera/features/rooms/services/power_level_service.dart';
import 'package:kohera/shared/widgets/user_avatar.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

/// Opens the member profile sheet for [user] in [room].
///
/// Shows avatar, display name, Matrix ID, presence and role, plus a
/// "Send message" action (others only) and moderation actions when the
/// caller has permission. Reused by the room members list and chat avatars.
Future<void> showMemberSheet(
  BuildContext context, {
  required Room room,
  required User user,
}) {
  final matrix = context.read<MatrixService>();
  final isMe = user.id == room.client.userID;
  final ownLevel = room.getPowerLevelByUserId(room.client.userID!);

  Future<void> startDm() async {
    if (!context.mounted) return;
    final selection = context.read<SelectionService>();
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final client = matrix.client;
      final dmRoomId = await client.startDirectChat(
        user.id,
        enableEncryption: true,
      );
      if (client.getRoomById(dmRoomId) == null) {
        await client
            .waitForRoomInSync(dmRoomId, join: true)
            .timeout(const Duration(seconds: 30));
      }
      selection.selectRoom(dmRoomId);
      router.goNamed(
        Routes.room,
        pathParameters: {RouteParams.roomId: dmRoomId},
      );
    } catch (e) {
      debugPrint('[Kohera] Start DM failed: $e');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Failed to start chat: ${MatrixService.friendlyAuthError(e)}',
          ),
        ),
      );
    }
  }

  return showDialog<void>(
    context: context,
    builder: (ctx) => MemberSheetDialog(
      user: user,
      room: room,
      presence: matrix.presence,
      ownLevel: ownLevel,
      isMe: isMe,
      onStartDm: isMe ? null : startDm,
    ),
  );
}

// ── Member sheet dialog ────────────────────────────────────────

class MemberSheetDialog extends StatefulWidget {
  const MemberSheetDialog({
    required this.user,
    required this.room,
    required this.presence,
    required this.ownLevel,
    required this.isMe,
    this.onStartDm,
    super.key,
  });

  final User user;
  final Room room;
  final PresenceService presence;
  final int ownLevel;
  final bool isMe;
  final Future<void> Function()? onStartDm;

  @override
  State<MemberSheetDialog> createState() => _MemberSheetDialogState();
}

class _MemberSheetDialogState extends State<MemberSheetDialog> {
  bool _roleLoading = false;
  String? _roleError;
  bool _actionLoading = false;
  String? _actionError;
  StreamSubscription<SyncUpdate>? _syncSub;
  Timer? _syncDebounce;

  @override
  void initState() {
    super.initState();
    _syncSub = widget.room.client.onSync.stream.listen(_onSync);
  }

  @override
  void dispose() {
    _syncDebounce?.cancel();
    unawaited(_syncSub?.cancel());
    super.dispose();
  }

  void _onSync(SyncUpdate update) {
    final stateEvents =
        update.rooms?.join?[widget.room.id]?.state ?? [];
    if (!stateEvents.any((e) => e.type == EventTypes.RoomPowerLevels)) return;
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _changeRole(RoomRole newRole, int currentPowerLevel) async {
    final currentRole = RoomRole.fromPowerLevel(currentPowerLevel);
    if (newRole == currentRole) return;

    // Require explicit confirmation before demoting another admin.
    if (currentPowerLevel >= 100) {
      final displayName = widget.user.displayName ?? widget.user.id;
      final confirmed = await confirmDialog(
        context,
        title: 'Demote admin?',
        message: 'This will demote $displayName from admin. Are you sure?',
        confirmLabel: 'Demote',
        destructive: true,
      );
      if (!confirmed || !mounted) return;
    }

    setState(() {
      _roleLoading = true;
      _roleError = null;
    });
    try {
      await PowerLevelService.update(
        widget.room,
        PowerLevelPatch(users: {widget.user.id: newRole.toPowerLevel()}),
      );
    } on PowerLevelException catch (e) {
      if (mounted) setState(() => _roleError = e.message);
    } finally {
      if (mounted) setState(() => _roleLoading = false);
    }
  }

  Future<void> _kick() async {
    final displayName = widget.user.displayName ?? widget.user.id;
    final cs = Theme.of(context).colorScheme;
    final reason = await _promptModerationReason(
      title: 'Kick member?',
      message: 'Remove $displayName from the room?',
      confirmLabel: 'Kick',
      cs: cs,
    );
    if (reason == null || !mounted) return;
    setState(() {
      _actionLoading = true;
      _actionError = null;
    });
    try {
      await widget.room.client.kick(
        widget.room.id,
        widget.user.id,
        reason: reason.isEmpty ? null : reason,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('[Kohera] Kick failed: $e');
      if (mounted) {
        setState(() {
          _actionLoading = false;
          _actionError = MatrixService.friendlyAuthError(e);
        });
      }
    }
  }

  Future<void> _ban() async {
    final displayName = widget.user.displayName ?? widget.user.id;
    final cs = Theme.of(context).colorScheme;
    final reason = await _promptModerationReason(
      title: 'Ban member?',
      message: "Ban $displayName from this room? They won't be able to rejoin.",
      confirmLabel: 'Ban',
      cs: cs,
    );
    if (reason == null || !mounted) return;
    setState(() {
      _actionLoading = true;
      _actionError = null;
    });
    try {
      await widget.room.client.ban(
        widget.room.id,
        widget.user.id,
        reason: reason.isEmpty ? null : reason,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('[Kohera] Ban failed: $e');
      if (mounted) {
        setState(() {
          _actionLoading = false;
          _actionError = MatrixService.friendlyAuthError(e);
        });
      }
    }
  }

  Future<void> _unban() async {
    final displayName = widget.user.displayName ?? widget.user.id;
    final confirmed = await confirmDialog(
      context,
      title: 'Unban member?',
      message: 'Allow $displayName to rejoin the room?',
      confirmLabel: 'Unban',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _actionLoading = true;
      _actionError = null;
    });
    try {
      await widget.room.client.unban(widget.room.id, widget.user.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('[Kohera] Unban failed: $e');
      if (mounted) {
        setState(() {
          _actionLoading = false;
          _actionError = MatrixService.friendlyAuthError(e);
        });
      }
    }
  }

  Future<String?> _promptModerationReason({
    required String title,
    required String message,
    required String confirmLabel,
    required ColorScheme cs,
  }) {
    return showDialog<String?>(
      context: context,
      builder: (dCtx) => _ModerationReasonDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        confirmColor: cs.error,
        onConfirmColor: cs.onError,
      ),
    );
  }

  List<DropdownMenuItem<RoomRole>> _buildRoleItems(int powerLevel) {
    final presets = [
      const RoomRole.admin(),
      const RoomRole.moderator(),
      const RoomRole.member(),
    ];

    final items = <DropdownMenuItem<RoomRole>>[];

    // If the current level doesn't match a preset, prepend it as a
    // display-only Custom item so the dropdown shows the right selection.
    final isCustom = !presets.any((r) => r.toPowerLevel() == powerLevel);
    if (isCustom) {
      final custom = RoomRole.fromPowerLevel(powerLevel);
      items.add(DropdownMenuItem(value: custom, child: Text(custom.label)));
    }

    for (final role in presets) {
      final canAssign = RoomRole.canAssignRole(
        target: role,
        ownLevel: widget.ownLevel,
        targetCurrentLevel: powerLevel,
      );
      items.add(DropdownMenuItem(
        value: role,
        enabled: canAssign,
        child: Text(
          role.label,
          style: canAssign
              ? null
              : TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.38),
                ),
        ),
      ),);
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final user = widget.user;
    final room = widget.room;
    final powerLevel = room.getPowerLevelByUserId(user.id);
    final currentRole = RoomRole.fromPowerLevel(powerLevel);
    final displayName = user.displayName ?? user.id;
    final isBanned = user.membership == Membership.ban;

    final canChangeRole = !widget.isMe &&
        room.canChangePowerLevel &&
        powerLevel < widget.ownLevel;
    final canKick = !widget.isMe &&
        room.canKick &&
        powerLevel < widget.ownLevel &&
        !isBanned;
    final canBan = !widget.isMe &&
        room.canBan &&
        powerLevel < widget.ownLevel &&
        !isBanned;
    final canUnban = !widget.isMe && room.canBan && isBanned;

    return SimpleDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      title: Column(
        children: [
          UserAvatar(
            client: room.client,
            userId: user.id,
            avatarUrl: user.avatarUrl,
            presence: widget.presence,
            size: 64,
          ),
          const SizedBox(height: 12),
          Text(
            displayName,
            style: tt.titleMedium,
            textAlign: TextAlign.center,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: SelectableText(
                  user.id,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_outlined),
                iconSize: 14,
                visualDensity: VisualDensity.compact,
                tooltip: 'Copy MXID',
                color: cs.onSurfaceVariant,
                onPressed: () {
                  unawaited(Clipboard.setData(ClipboardData(text: user.id)));
                  context.showSnack('Copied to clipboard');
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _powerLevelDescription(powerLevel),
            style: tt.bodySmall?.copyWith(color: cs.primary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      children: [
        // ── Role section ──────────────────────────────────────
        if (!widget.isMe) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(
              'Role',
              style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: _roleLoading
                ? const LinearProgressIndicator()
                : DropdownButton<RoomRole>(
                    isExpanded: true,
                    value: currentRole,
                    onChanged: canChangeRole
                        ? (newRole) {
                            if (newRole != null) {
                              unawaited(_changeRole(newRole, powerLevel));
                            }
                          }
                        : null,
                    items: _buildRoleItems(powerLevel),
                  ),
          ),
          if (_roleError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Text(
                _roleError!,
                style: TextStyle(color: cs.error, fontSize: 12),
              ),
            ),
          const Divider(height: 1),
        ],

        // ── Action feedback ───────────────────────────────────
        if (_actionLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: LinearProgressIndicator(),
          ),
        if (_actionError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
            child: Text(
              _actionError!,
              style: TextStyle(color: cs.error, fontSize: 12),
            ),
          ),

        // ── Actions ───────────────────────────────────────────
        if (!widget.isMe && widget.onStartDm != null)
          SimpleDialogOption(
            onPressed: _actionLoading
                ? null
                : () async {
                    Navigator.pop(context);
                    await widget.onStartDm!();
                  },
            child: const Row(
              children: [
                Icon(Icons.chat_outlined),
                SizedBox(width: 16),
                Text('Send message'),
              ],
            ),
          ),
        if (canKick)
          SimpleDialogOption(
            onPressed: _actionLoading ? null : _kick,
            child: Row(
              children: [
                Icon(Icons.person_remove_outlined, color: cs.error),
                const SizedBox(width: 16),
                Text('Kick', style: TextStyle(color: cs.error)),
              ],
            ),
          ),
        if (canBan)
          SimpleDialogOption(
            onPressed: _actionLoading ? null : _ban,
            child: Row(
              children: [
                Icon(Icons.block_rounded, color: cs.error),
                const SizedBox(width: 16),
                Text('Ban', style: TextStyle(color: cs.error)),
              ],
            ),
          ),
        if (canUnban)
          SimpleDialogOption(
            onPressed: _actionLoading ? null : _unban,
            child: Row(
              children: [
                Icon(Icons.lock_open_outlined, color: cs.primary),
                const SizedBox(width: 16),
                Text('Unban', style: TextStyle(color: cs.primary)),
              ],
            ),
          ),
      ],
    );
  }

  String _powerLevelDescription(int level) {
    if (level >= 100) return 'Admin (power level $level)';
    if (level >= 50) return 'Moderator (power level $level)';
    if (level > 0) return 'Power level $level';
    return 'Member';
  }
}

// ── Moderation reason dialog ───────────────────────────────────

class _ModerationReasonDialog extends StatefulWidget {
  const _ModerationReasonDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
    required this.onConfirmColor,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final Color confirmColor;
  final Color onConfirmColor;

  @override
  State<_ModerationReasonDialog> createState() =>
      _ModerationReasonDialogState();
}

class _ModerationReasonDialogState extends State<_ModerationReasonDialog> {
  late final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.message),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            textInputAction: TextInputAction.done,
            maxLength: 240,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) =>
                Navigator.pop(context, _controller.text.trim()),
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
            backgroundColor: widget.confirmColor,
            foregroundColor: widget.onConfirmColor,
          ),
          onPressed: () =>
              Navigator.pop(context, _controller.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
