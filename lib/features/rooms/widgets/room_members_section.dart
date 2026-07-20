import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/services/sub_services/presence_service.dart';
import 'package:kohera/core/utils/confirm_dialog.dart';
import 'package:kohera/features/rooms/models/kohera_room_member.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/user_avatar.dart';

/// Displays a scrollable list of room members with role badges.
/// Shows the first 5 with an expand option and a search filter.
///
/// This widget is SDK-free — all data comes from [KoheraRoomMemberList]
/// and all interactions are handled by the [onMemberTap] callback.
class RoomMembersSection extends StatefulWidget {
  const RoomMembersSection({
    required this.members,
    required this.onMemberTap,
    required this.avatarResolver,
    required this.presence,
    this.canBan = false,
    this.onUnban,
    super.key,
  });

  final KoheraRoomMemberList members;
  final void Function(KoheraRoomMember member) onMemberTap;
  final AvatarResolver avatarResolver;
  final PresenceService presence;

  /// Whether the current user may unban members in this room. Gates the
  /// per-row Unban action in the banned-users section.
  final bool canBan;

  /// Called when the user confirms an unban from the banned-users section.
  final Future<void> Function(KoheraRoomMember member)? onUnban;

  @override
  State<RoomMembersSection> createState() => _RoomMembersSectionState();
}

class _RoomMembersSectionState extends State<RoomMembersSection> {
  bool _expanded = false;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final next = _searchController.text.trim().toLowerCase();
    if (next == _query) return;
    setState(() => _query = next);
  }

  List<KoheraRoomMember> _filtered() {
    if (_query.isEmpty) return widget.members.members;
    return widget.members.members.where((m) {
      final name = m.displayname.toLowerCase();
      final id = m.userId.toLowerCase();
      return name.contains(_query) || id.contains(_query);
    }).toList();
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
        if (widget.members.isEmpty)
          const SizedBox.shrink()
        else ...[
          if (widget.members.members.length > 5)
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
                  _MemberTile(
                    member: member,
                    avatarResolver: widget.avatarResolver,
                    presence: widget.presence,
                    onTap: () => widget.onMemberTap(member),
                  ),
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
        if (widget.members.bannedMembers.isNotEmpty)
          _BannedMembersSection(
            bannedMembers: widget.members.bannedMembers,
            canBan: widget.canBan,
            avatarResolver: widget.avatarResolver,
            presence: widget.presence,
            onUnban: widget.onUnban,
            onMemberTap: widget.onMemberTap,
          ),
      ],
    );
  }
}

// ── Banned members section ────────────────────────────────────

class _BannedMembersSection extends StatefulWidget {
  const _BannedMembersSection({
    required this.bannedMembers,
    required this.canBan,
    required this.avatarResolver,
    required this.presence,
    required this.onMemberTap,
    this.onUnban,
  });

  final List<KoheraRoomMember> bannedMembers;
  final bool canBan;
  final AvatarResolver avatarResolver;
  final PresenceService presence;
  final void Function(KoheraRoomMember member) onMemberTap;
  final Future<void> Function(KoheraRoomMember member)? onUnban;

  @override
  State<_BannedMembersSection> createState() => _BannedMembersSectionState();
}

class _BannedMembersSectionState extends State<_BannedMembersSection> {
  bool _expanded = false;
  String? _unbanningId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final visible =
        _expanded ? widget.bannedMembers : widget.bannedMembers.take(3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
          child: Text(
            'BANNED',
            style: tt.labelSmall?.copyWith(
              color: cs.error,
              letterSpacing: 1.5,
            ),
          ),
        ),
        for (final member in visible)
          _BannedMemberTile(
            member: member,
            avatarResolver: widget.avatarResolver,
            presence: widget.presence,
            canUnban: widget.canBan && widget.onUnban != null,
            unbanning: _unbanningId == member.userId,
            onTap: () => widget.onMemberTap(member),
            onUnban: () => unawaited(_unban(member)),
          ),
        if (!_expanded && widget.bannedMembers.length > 3)
          TextButton(
            onPressed: () => setState(() => _expanded = true),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Show all ${widget.bannedMembers.length} banned'),
            ),
          ),
      ],
    );
  }

  Future<void> _unban(KoheraRoomMember member) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Unban member?',
      message: 'Allow ${member.displayname} to rejoin the room?',
      confirmLabel: 'Unban',
    );
    if (!confirmed || !mounted) return;
    setState(() => _unbanningId = member.userId);
    try {
      await widget.onUnban?.call(member);
    } finally {
      if (mounted) setState(() => _unbanningId = null);
    }
  }
}

class _BannedMemberTile extends StatelessWidget {
  const _BannedMemberTile({
    required this.member,
    required this.avatarResolver,
    required this.presence,
    required this.canUnban,
    required this.unbanning,
    required this.onTap,
    required this.onUnban,
  });

  final KoheraRoomMember member;
  final AvatarResolver avatarResolver;
  final PresenceService presence;
  final bool canUnban;
  final bool unbanning;
  final VoidCallback onTap;
  final VoidCallback onUnban;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListTile(
      dense: true,
      leading: UserAvatar(
        avatarResolver: avatarResolver,
        userId: member.userId,
        avatarUrl: member.avatarUrl,
        displayname: member.displayname,
        presence: presence,
        size: 32,
      ),
      title: Text(
        member.displayname,
        overflow: TextOverflow.ellipsis,
        style: tt.bodyMedium,
      ),
      subtitle: Text(
        member.userId,
        style: tt.bodySmall,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: canUnban
          ? unbanning
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  tooltip: 'Unban',
                  icon: const Icon(Icons.lock_open_outlined),
                  color: cs.primary,
                  onPressed: onUnban,
                )
          : null,
      onTap: onTap,
    );
  }
}

// ── Member tile ────────────────────────────────────────────────

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.avatarResolver,
    required this.presence,
    required this.onTap,
  });

  final KoheraRoomMember member;
  final AvatarResolver avatarResolver;
  final PresenceService presence;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final powerLevel = member.powerLevel;

    return ListTile(
      dense: true,
      leading: UserAvatar(
        avatarResolver: avatarResolver,
        userId: member.userId,
        avatarUrl: member.avatarUrl,
        displayname: member.displayname,
        presence: presence,
        size: 32,
      ),
      title: Text(
        member.displayname,
        overflow: TextOverflow.ellipsis,
        style: tt.bodyMedium,
      ),
      subtitle: Text(
        member.userId,
        style: tt.bodySmall,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _roleBadge(powerLevel, cs),
      onTap: onTap,
    );
  }

  Widget? _roleBadge(int powerLevel, ColorScheme cs) {
    if (powerLevel >= 100) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
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
          borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
        ),
        child: Text(
          'Mod',
          style: TextStyle(fontSize: 11, color: cs.onTertiaryContainer),
        ),
      );
    }
    return null;
  }
}
