import 'package:flutter/material.dart';
import 'package:kohera/core/services/sub_services/presence_service.dart';
import 'package:kohera/core/theme/k_icons.dart';
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
    super.key,
  });

  final KoheraRoomMemberList members;
  final void Function(KoheraRoomMember member) onMemberTap;
  final AvatarResolver avatarResolver;
  final PresenceService presence;

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
                  prefixIcon: const Icon(KIcons.search, size: 20),
                  hintText: 'Search members',
                  border: const OutlineInputBorder(),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(KIcons.close, size: 20),
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
      ],
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
