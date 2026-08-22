import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/data/models/kohera_push_rule_state.dart';
import 'package:kohera/data/models/kohera_room_member.dart';
import 'package:kohera/data/repositories/media_repository.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/data/repositories/space_repository.dart';
import 'package:kohera/data/repositories/user_repository.dart';
import 'package:kohera/features/rooms/services/invite_user_dialog_params.dart';
import 'package:kohera/features/rooms/services/join_access_controller.dart';
import 'package:kohera/features/rooms/services/member_sheet_launcher.dart';
import 'package:kohera/features/rooms/widgets/admin_settings_section.dart';
import 'package:kohera/features/rooms/widgets/invite_user_dialog.dart';
import 'package:kohera/features/rooms/widgets/room_members_section.dart';
import 'package:kohera/features/spaces/widgets/notification_radio_group.dart';
import 'package:kohera/features/spaces/widgets/space_action_dialog.dart';
import 'package:kohera/features/spaces/widgets/space_context_menu.dart';
import 'package:kohera/shared/widgets/avatar_edit_overlay.dart';
import 'package:kohera/shared/widgets/detail_action_button.dart';
import 'package:kohera/shared/widgets/joined_member_count.dart';
import 'package:provider/provider.dart';

/// Displays space details: header, actions, members, and admin controls.
///
/// When [isFullPage] is true, wraps itself in a Scaffold with an AppBar
/// (for mobile/tablet push route). Otherwise renders as a bare panel
/// (for the desktop content pane).
class SpaceDetailsPanel extends StatefulWidget {
  const SpaceDetailsPanel({
    required this.spaceId, super.key,
    this.isFullPage = false,
  });

  final String spaceId;
  final bool isFullPage;

  @override
  State<SpaceDetailsPanel> createState() => _SpaceDetailsPanelState();
}

class _SpaceDetailsPanelState extends State<SpaceDetailsPanel> {
  final Set<String> _inFlight = {};
  String? _error;
  KoheraRoomMemberList? _memberList;
  bool _loadingMembers = false;
  int? _lastMemberCount;
  bool _canBan = false;
  int _memberLoadGen = 0;
  StreamSubscription<dynamic>? _syncSub;
  Timer? _syncDebounce;

  bool get _loading => _inFlight.isNotEmpty;
  bool _busy(String action) => _inFlight.contains(action);

  // ── Lifecycle ───────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.read<SpaceRepository>().spaceExists(widget.spaceId)) {
        unawaited(_loadMembers(widget.spaceId));
      }
      _setupSyncListener();
    });
  }

  @override
  void didUpdateWidget(SpaceDetailsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final count =
        context.read<RoomRepository>().getRoomSummaryMemberCount(widget.spaceId);
    if (count != null && count != _lastMemberCount && !_loadingMembers) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadMembers(widget.spaceId));
      });
    }
  }

  @override
  void dispose() {
    _syncDebounce?.cancel();
    unawaited(_syncSub?.cancel());
    super.dispose();
  }

  void _setupSyncListener() {
    final roomRepo = context.read<RoomRepository>();
    final spaceRepo = context.read<SpaceRepository>();
    unawaited(_syncSub?.cancel());
    _syncSub = roomRepo.onSync.listen((update) {
      final stateEvents = update.rooms?.join?[widget.spaceId]?.state ?? [];
      final hasPowerLevelChanges =
          stateEvents.any((e) => e.type == 'm.room.power_levels');
      _syncDebounce?.cancel();
      _syncDebounce = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() {});
        if (hasPowerLevelChanges &&
            _memberList != null &&
            spaceRepo.spaceExists(widget.spaceId)) {
          unawaited(_loadMembers(widget.spaceId));
        }
      });
    });
  }

  // ── Actions ────────────────────────────────────────────────

  Future<void> _loadMembers(String spaceId) async {
    final gen = ++_memberLoadGen;
    final roomRepo = context.read<RoomRepository>();
    if (!context.read<SpaceRepository>().spaceExists(spaceId)) return;
    setState(() => _loadingMembers = true);
    try {
      final list = await roomRepo.memberListFor(spaceId);
      if (!mounted || gen != _memberLoadGen || list == null) return;
      setState(() {
        _memberList = list;
        _loadingMembers = false;
        _lastMemberCount = list.memberCount;
        _canBan = roomRepo.getRoomCanBan(spaceId);
      });
    } catch (e) {
      debugPrint('[Kohera] Failed to load members: $e');
      if (mounted) {
        setState(() => _loadingMembers = false);
      }
    }
  }

  Future<void> _showMemberSheet(
    BuildContext context,
    String spaceId,
    KoheraRoomMember member,
  ) {
    if (!context.read<SpaceRepository>().spaceExists(spaceId)) {
      return Future.value();
    }
    return showRoomMemberSheet(context, roomId: spaceId, member: member);
  }

  Future<void> _unbanMember(
    BuildContext context,
    String spaceId,
    KoheraRoomMember member,
  ) async {
    if (!context.read<SpaceRepository>().spaceExists(spaceId)) return;
    await unbanRoomMember(context, context.read<RoomRepository>(), spaceId, member);
    unawaited(_loadMembers(spaceId));
  }

  Future<void> _run(String action, Future<void> Function() task) async {
    setState(() {
      _inFlight.add(action);
      _error = null;
    });
    try {
      await task();
    } catch (e) {
      debugPrint('[Kohera] $action failed: $e');
      if (mounted) setState(() => _error = MatrixService.friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _inFlight.remove(action));
    }
  }

  Future<void> _showInviteDialog(String spaceId) async {
    final spaceRepo = context.read<SpaceRepository>();
    if (!spaceRepo.spaceExists(spaceId) || !mounted) return;

    final result = await InviteUserDialog.show(
      context,
      params: inviteUserDialogParams(
        spaceId,
        context.read<RoomRepository>(),
        context.read<UserRepository>(),
      ),
    );
    if (result == null || !mounted) return;

    await _run('invite', () async {
      await spaceRepo.invite(spaceId, result);
      if (mounted) context.showSnack('Invited $result');
    });
  }

  Future<void> _confirmLeave(String spaceId) async {
    if (!mounted) return;
    await _run('leave', () => handleLeaveSpace(context, spaceId));
  }

  Future<void> _setPushRule(String spaceId, KoheraPushRuleState state) {
    final spaceRepo = context.read<SpaceRepository>();
    return _run('pushRule', () => spaceRepo.setPushRuleState(spaceId, state));
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final summary = context.watch<RoomRepository>().summaryFor(widget.spaceId);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (summary == null) {
      final body = Center(child: Text('Space not found', style: tt.bodyLarge));
      return widget.isFullPage ? Scaffold(appBar: AppBar(), body: body) : body;
    }

    final content = _buildContent(widget.spaceId, cs, tt);

    if (widget.isFullPage) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.goNamed(Routes.home),
          ),
          title: Text(summary.displayname),
        ),
        body: content,
      );
    }

    return Material(
      color: cs.surface,
      child: content,
    );
  }

  Widget _buildContent(String spaceId, ColorScheme cs, TextTheme tt) {
    // Initial member load is triggered in initState — no side effects in build.
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (_loading) const LinearProgressIndicator(),
        _buildHeader(spaceId, cs, tt),
        const Divider(),
        _buildActionsRow(spaceId, cs),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
          ),
        const Divider(),
        JoinAccessController(
          roomId: spaceId,
          candidatesBuilder: (ctx, roomId) =>
              ctx.read<SpaceRepository>().parentSpaceRefs(roomId),
        ),
        const Divider(),
        if (_memberList != null)
          RoomMembersSection(
            members: _memberList!,
            onMemberTap: (member) =>
                _showMemberSheet(context, spaceId, member),
            avatarResolver: context.read<MediaRepository>().avatarResolver,
            presence: context.read<UserRepository>(),
            canBan: _canBan,
            onUnban: (member) => _unbanMember(context, spaceId, member),
          ),
        const Divider(),
        _buildNotificationSection(spaceId, cs, tt),
        if (_canEditSpace(spaceId)) ...[
          const Divider(),
          AdminSettingsSection(
            permissions: context.read<RoomRepository>().permissionsFor(spaceId)!,
            onSaveName: (name) =>
                context.read<SpaceRepository>().setName(spaceId, name),
            onSaveTopic: (topic) =>
                context.read<SpaceRepository>().setDescription(spaceId, topic),
            onEnableEncryption: () =>
                context.read<SpaceRepository>().enableEncryption(spaceId),
          ),
        ],
      ],
    );
  }

  bool _canEditSpace(String spaceId) {
    final spaceRepo = context.read<SpaceRepository>();
    return spaceRepo.canEditName(spaceId) ||
        spaceRepo.canEditTopic(spaceId) ||
        spaceRepo.canChangePowerLevel(spaceId);
  }

  // ── Notification settings ──────────────────────────────────

  Widget _buildNotificationSection(String spaceId, ColorScheme cs, TextTheme tt) {
    final spaceRepo = context.read<SpaceRepository>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
          child: Text(
            'NOTIFICATIONS',
            style: tt.labelSmall?.copyWith(
              color: cs.primary,
              letterSpacing: 1.5,
            ),
          ),
        ),
        NotificationRadioGroup(
          groupValue: spaceRepo.pushRuleState(spaceId),
          onChanged: _busy('pushRule')
              ? null
              : (v) => _setPushRule(spaceId, v!),
        ),
      ],
    );
  }

  // ── Header ─────────────────────────────────────────────────

  Widget _buildHeader(String spaceId, ColorScheme cs, TextTheme tt) {
    final roomRepo = context.read<RoomRepository>();
    final spaceRepo = context.read<SpaceRepository>();
    final summary = roomRepo.summaryFor(spaceId);
    if (summary == null) return const SizedBox.shrink();
    final topic = summary.topic ?? '';
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          AvatarEditOverlay(
            roomId: spaceId,
            summary: summary,
            canEditAvatar: spaceRepo.canEditAvatar(spaceId),
            avatarResolver: context.read<MediaRepository>().avatarResolver,
            onSetAvatar: (bytes, filename) =>
                spaceRepo.setAvatar(spaceId, bytes, filename),
          ),
          const SizedBox(height: 12),
          Text(
            summary.displayname,
            style: tt.titleLarge,
            textAlign: TextAlign.center,
          ),
          if (topic.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              topic,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 4),
          JoinedMemberCount(
            roomId: spaceId,
            summaryMemberCount:
                roomRepo.getRoomSummaryMemberCount(spaceId) ?? 0,
            participantListComplete:
                roomRepo.getRoomParticipantListComplete(spaceId),
            resolveMemberCount: roomRepo.resolveMemberCount,
            builder: (context, memberCount) => Text(
              memberCount == 1 ? '1 member' : '$memberCount members',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  // ── Actions row ────────────────────────────────────────────

  Widget _buildActionsRow(String spaceId, ColorScheme cs) {
    final canInvite = context.read<SpaceRepository>().canInvite(spaceId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          DetailActionButton(
            icon: Icons.meeting_room_outlined,
            label: 'Browse rooms',
            onTap: () => _browseSpaceRooms(spaceId),
          ),
          if (canInvite)
            DetailActionButton(
              icon: Icons.person_add_outlined,
              label: 'Invite',
              onTap: _busy('invite') ? null : () => _showInviteDialog(spaceId),
            ),
          DetailActionButton(
            icon: Icons.exit_to_app_rounded,
            label: 'Leave',
            color: cs.error,
            onTap: _busy('leave') ? null : () => _confirmLeave(spaceId),
          ),
        ],
      ),
    );
  }

  Future<void> _browseSpaceRooms(String spaceId) async {
    final matrix = context.read<MatrixService>();
    final roomRepo = context.read<RoomRepository>();
    final summary = roomRepo.summaryFor(spaceId);
    if (summary == null) return;
    await SpaceDiscoveryDialog.showSpaceRooms(
      context,
      matrixService: matrix,
      roomId: spaceId,
      name: summary.displayname,
      avatar: roomRepo.avatarUri(spaceId),
      canonicalAlias: summary.canonicalAlias,
    );
  }
}
