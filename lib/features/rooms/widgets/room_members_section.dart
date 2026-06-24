import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/rooms/widgets/member_sheet_dialog.dart';
import 'package:kohera/shared/widgets/user_avatar.dart';
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
      leading: UserAvatar(
        client: widget.room.client,
        userId: widget.user.id,
        avatarUrl: widget.user.avatarUrl,
        presence: context.read<MatrixService>().presence,
        size: 32,
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
    unawaited(showMemberSheet(
      context,
      room: widget.room,
      user: widget.user,
    ),);
  }
}
