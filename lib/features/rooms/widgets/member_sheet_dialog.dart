import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/core/services/sub_services/presence_service.dart';
import 'package:kohera/core/utils/confirm_dialog.dart';
import 'package:kohera/features/rooms/models/kohera_room_member.dart';
import 'package:kohera/features/rooms/models/room_role.dart';
import 'package:kohera/features/rooms/services/power_level_service.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/user_avatar.dart';

/// Opens the member profile sheet for [member].
///
/// Shows avatar, display name, Matrix ID, presence and role, plus a
/// "Send message" action (others only) and moderation actions when the
/// caller has permission. All SDK work is done by the caller — this
/// function and [MemberSheetDialog] are SDK-free.
Future<void> showMemberSheetDialog(
  BuildContext context, {
  required KoheraRoomMember member,
  required bool isMe,
  required int ownLevel,
  required bool canChangeRole,
  required bool canKick,
  required bool canBan,
  required AvatarResolver avatarResolver,
  required PresenceService presence,
  Future<void> Function()? onStartDm,
  Future<void> Function(int newLevel)? onRoleChange,
  Future<void> Function(String? reason)? onKick,
  Future<void> Function(String? reason)? onBan,
  Future<void> Function(String? reason)? onUnban,
  String Function(Object error)? formatError,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => MemberSheetDialog(
      member: member,
      isMe: isMe,
      ownLevel: ownLevel,
      canChangeRole: canChangeRole,
      canKick: canKick,
      canBan: canBan,
      avatarResolver: avatarResolver,
      presence: presence,
      onStartDm: onStartDm,
      onRoleChange: onRoleChange,
      onKick: onKick,
      onBan: onBan,
      onUnban: onUnban,
      formatError: formatError,
    ),
  );
}

// ── Member sheet dialog ────────────────────────────────────────

class MemberSheetDialog extends StatefulWidget {
  const MemberSheetDialog({
    required this.member,
    required this.isMe,
    required this.ownLevel,
    required this.canChangeRole,
    required this.canKick,
    required this.canBan,
    required this.avatarResolver,
    required this.presence,
    this.onStartDm,
    this.onRoleChange,
    this.onKick,
    this.onBan,
    this.onUnban,
    this.formatError,
    super.key,
  });

  final KoheraRoomMember member;
  final bool isMe;
  final int ownLevel;
  final bool canChangeRole;
  final bool canKick;
  final bool canBan;
  final AvatarResolver avatarResolver;
  final PresenceService presence;
  final Future<void> Function()? onStartDm;
  final Future<void> Function(int newLevel)? onRoleChange;
  final Future<void> Function(String? reason)? onKick;
  final Future<void> Function(String? reason)? onBan;
  final Future<void> Function(String? reason)? onUnban;

  /// Formats caught errors for user-facing display.
  /// When null, errors fall back to `e.toString()`.
  final String Function(Object error)? formatError;

  @override
  State<MemberSheetDialog> createState() => _MemberSheetDialogState();
}

class _MemberSheetDialogState extends State<MemberSheetDialog> {
  bool _roleLoading = false;
  String? _roleError;
  bool _actionLoading = false;
  String? _actionError;
  late int _currentPowerLevel;

  @override
  void initState() {
    super.initState();
    _currentPowerLevel = widget.member.powerLevel;
  }

  Future<void> _changeRole(RoomRole newRole, int currentPowerLevel) async {
    final currentRole = RoomRole.fromPowerLevel(currentPowerLevel);
    if (newRole == currentRole) return;

    // Require explicit confirmation before demoting another admin.
    if (currentPowerLevel >= 100) {
      final displayName = widget.member.displayname;
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
      await widget.onRoleChange?.call(newRole.toPowerLevel());
      if (mounted) {
        setState(() {
          _currentPowerLevel = newRole.toPowerLevel();
          _roleLoading = false;
        });
      }
    } on PowerLevelException catch (e) {
      if (mounted) {
        setState(() {
          _roleError = e.message;
          _roleLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _roleError = widget.formatError?.call(e) ?? e.toString();
          _roleLoading = false;
        });
      }
    }
  }

  Future<void> _kick() async {
    final displayName = widget.member.displayname;
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
      await widget.onKick?.call(reason.isEmpty ? null : reason);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('[Kohera] Kick failed: $e');
      if (mounted) {
        setState(() {
          _actionLoading = false;
          _actionError = widget.formatError?.call(e) ?? e.toString();
        });
      }
    }
  }

  Future<void> _ban() async {
    final displayName = widget.member.displayname;
    final cs = Theme.of(context).colorScheme;
    final reason = await _promptModerationReason(
      title: 'Ban member?',
      message:
          "Ban $displayName from this room? They won't be able to rejoin.",
      confirmLabel: 'Ban',
      cs: cs,
    );
    if (reason == null || !mounted) return;
    setState(() {
      _actionLoading = true;
      _actionError = null;
    });
    try {
      await widget.onBan?.call(reason.isEmpty ? null : reason);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('[Kohera] Ban failed: $e');
      if (mounted) {
        setState(() {
          _actionLoading = false;
          _actionError = widget.formatError?.call(e) ?? e.toString();
        });
      }
    }
  }

  Future<void> _unban() async {
    final displayName = widget.member.displayname;
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
      await widget.onUnban?.call(null);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('[Kohera] Unban failed: $e');
      if (mounted) {
        setState(() {
          _actionLoading = false;
          _actionError = widget.formatError?.call(e) ?? e.toString();
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
      items.add(
        DropdownMenuItem(
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
        ),
      );
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final member = widget.member;
    final isBanned = member.isBanned;
    final powerLevel = _currentPowerLevel;
    final currentRole = RoomRole.fromPowerLevel(powerLevel);
    final displayName = member.displayname;

    final canKick = widget.canKick && !isBanned;
    final canBan = widget.canBan && !isBanned;
    final canUnban = widget.canBan && isBanned;

    return SimpleDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      title: Column(
        children: [
          UserAvatar(
            avatarResolver: widget.avatarResolver,
            userId: member.userId,
            avatarUrl: member.avatarUrl,
            displayname: member.displayname,
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
                  member.userId,
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
                  unawaited(
                    Clipboard.setData(ClipboardData(text: member.userId)),
                  );
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
                    onChanged: widget.canChangeRole
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
            onSubmitted: (_) => Navigator.pop(context, _controller.text.trim()),
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
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
