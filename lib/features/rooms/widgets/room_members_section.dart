import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/core/utils/sender_color.dart';
import 'package:kohera/features/rooms/models/room_role.dart';
import 'package:kohera/features/rooms/services/power_level_service.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

/// Displays a scrollable list of room members with role badges.
/// Loads members asynchronously and shows the first 5 with an expand option.
class RoomMembersSection extends StatefulWidget {
  const RoomMembersSection({required this.room, super.key});

  final Room room;

  @override
  State<RoomMembersSection> createState() => _RoomMembersSectionState();
}

class _RoomMembersSectionState extends State<RoomMembersSection> {
  List<User> _members = [];
  bool _loading = true;
  bool _expanded = false;
  int? _lastMemberCount;
  int _loadGeneration = 0;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  StreamSubscription<SyncUpdate>? _syncSub;
  Timer? _syncDebounce;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMembers());
    _searchController.addListener(_onSearchChanged);
    _syncSub = widget.room.client.onSync.stream.listen(_onSync);
  }

  @override
  void dispose() {
    _syncDebounce?.cancel();
    unawaited(_syncSub?.cancel());
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSync(SyncUpdate update) {
    final stateEvents =
        update.rooms?.join?[widget.room.id]?.state ?? [];
    if (!stateEvents.any((e) => e.type == EventTypes.RoomPowerLevels)) return;
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) unawaited(_loadMembers());
    });
  }

  void _onSearchChanged() {
    final next = _searchController.text.trim().toLowerCase();
    if (next == _query) return;
    setState(() => _query = next);
  }

  List<User> _filtered() {
    if (_query.isEmpty) return _members;
    return _members.where((u) {
      final name = (u.displayName ?? '').toLowerCase();
      final id = u.id.toLowerCase();
      return name.contains(_query) || id.contains(_query);
    }).toList();
  }

  @override
  void didUpdateWidget(RoomMembersSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentCount = widget.room.summary.mJoinedMemberCount;
    if (currentCount != _lastMemberCount) {
      unawaited(_loadMembers());
    }
  }

  Future<void> _loadMembers() async {
    final gen = ++_loadGeneration;
    setState(() => _loading = true);
    try {
      final members = await widget.room.requestParticipants([Membership.join]);
      if (!mounted || gen != _loadGeneration) return;
      // Sort: admins first, then mods, then alphabetical.
      members.sort((a, b) {
        final pa = widget.room.getPowerLevelByUserId(a.id);
        final pb = widget.room.getPowerLevelByUserId(b.id);
        if (pa != pb) return pb.compareTo(pa);
        final na = a.displayName ?? a.id;
        final nb = b.displayName ?? b.id;
        return na.compareTo(nb);
      });
      setState(() {
        _members = members;
        _loading = false;
        _lastMemberCount = widget.room.summary.mJoinedMemberCount;
      });
    } catch (e) {
      debugPrint('[Kohera] Failed to load members: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _lastMemberCount = widget.room.summary.mJoinedMemberCount;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
          child: Text(
            'MEMBERS',
            style: tt.labelSmall?.copyWith(
              color: cs.primary,
              letterSpacing: 1.5,
            ),
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          if (_members.length > 5)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: 'Search members',
                  border: const OutlineInputBorder(),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: _searchController.clear,
                        ),
                ),
              ),
            ),
          Builder(builder: (_) {
            final filtered = _filtered();
            if (filtered.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No members match "${_searchController.text}"',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              );
            }
            final showAll = _expanded || _query.isNotEmpty;
            final visible = showAll ? filtered : filtered.take(5);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final member in visible)
                  _MemberTile(user: member, room: widget.room),
                if (!showAll && filtered.length > 5)
                  TextButton(
                    onPressed: () => setState(() => _expanded = true),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Show all ${filtered.length} members'),
                    ),
                  ),
              ],
            );
          },),
        ],
      ],
    );
  }
}

// ── Member tile ────────────────────────────────────────────────

class _MemberTile extends StatefulWidget {
  const _MemberTile({required this.user, required this.room});

  final User user;
  final Room room;

  @override
  State<_MemberTile> createState() => _MemberTileState();
}

class _MemberTileState extends State<_MemberTile> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final powerLevel = widget.room.getPowerLevelByUserId(widget.user.id);
    final displayName = widget.user.displayName ?? widget.user.id;

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: senderColor(widget.user.id, cs),
        child: Text(
          displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: ThemeData.estimateBrightnessForColor(senderColor(widget.user.id, cs)) == Brightness.dark
                ? Colors.white
                : Colors.black,
          ),
        ),
      ),
      title: Text(
        displayName,
        overflow: TextOverflow.ellipsis,
        style: tt.bodyMedium,
      ),
      subtitle: Text(
        widget.user.id,
        style: tt.bodySmall,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _roleBadge(powerLevel, cs),
      onTap: _showMemberSheet,
    );
  }

  Widget? _roleBadge(int powerLevel, ColorScheme cs) {
    if (powerLevel >= 100) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'Admin',
          style: TextStyle(fontSize: 11, color: cs.onErrorContainer),
        ),
      );
    }
    if (powerLevel >= 50) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: cs.tertiaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'Mod',
          style: TextStyle(fontSize: 11, color: cs.onTertiaryContainer),
        ),
      );
    }
    return null;
  }

  void _showMemberSheet() {
    final matrix = context.read<MatrixService>();
    final isMe = widget.user.id == widget.room.client.userID;
    final ownLevel = widget.room.getPowerLevelByUserId(widget.room.client.userID!);

    unawaited(showDialog<void>(
      context: context,
      builder: (ctx) => _MemberSheetDialog(
        user: widget.user,
        room: widget.room,
        ownLevel: ownLevel,
        isMe: isMe,
        onStartDm: !isMe
            ? () async {
                if (!mounted) return;
                final selection = context.read<SelectionService>();
                final router = GoRouter.of(context);
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final client = matrix.client;
                  final dmRoomId = await client.startDirectChat(
                    widget.user.id,
                    enableEncryption: true,
                  );
                  if (client.getRoomById(dmRoomId) == null) {
                    await client
                        .waitForRoomInSync(dmRoomId, join: true)
                        .timeout(const Duration(seconds: 30));
                  }
                  if (!mounted) return;
                  selection.selectRoom(dmRoomId);
                  router.goNamed(
                    Routes.room,
                    pathParameters: {'roomId': dmRoomId},
                  );
                } catch (e) {
                  debugPrint('[Kohera] Start DM failed: $e');
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(content: Text('Failed to start chat: ${MatrixService.friendlyAuthError(e)}')),
                  );
                }
              }
            : null,
      ),
    ),);
  }
}

// ── Member sheet dialog ────────────────────────────────────────

class _MemberSheetDialog extends StatefulWidget {
  const _MemberSheetDialog({
    required this.user,
    required this.room,
    required this.ownLevel,
    required this.isMe,
    this.onStartDm,
  });

  final User user;
  final Room room;
  final int ownLevel;
  final bool isMe;
  final Future<void> Function()? onStartDm;

  @override
  State<_MemberSheetDialog> createState() => _MemberSheetDialogState();
}

class _MemberSheetDialogState extends State<_MemberSheetDialog> {
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
      final cs = Theme.of(context).colorScheme;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Demote admin?'),
          content: Text(
            'This will demote $displayName from admin. Are you sure?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Demote'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unban member?'),
        content: Text('Allow $displayName to rejoin the room?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unban'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
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

    final avatarColor = senderColor(user.id, cs);
    final avatarFg =
        ThemeData.estimateBrightnessForColor(avatarColor) == Brightness.dark
            ? Colors.white
            : Colors.black;

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
          CircleAvatar(
            radius: 32,
            backgroundColor: avatarColor,
            child: Text(
              displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: avatarFg,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            displayName,
            style: tt.titleMedium,
            textAlign: TextAlign.center,
          ),
          Text(
            user.id,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
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
