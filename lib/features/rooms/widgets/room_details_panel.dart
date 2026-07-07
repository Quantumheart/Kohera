import 'package:flutter/material.dart';
import 'package:kohera/core/models/kohera_push_rule_state.dart';
import 'package:kohera/core/routing/nav_helper.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/core/theme/k_icons.dart';
import 'package:kohera/core/utils/confirm_dialog.dart';
import 'package:kohera/features/rooms/models/kohera_device_key.dart';
import 'package:kohera/features/rooms/services/room_details_controller.dart';
import 'package:kohera/features/rooms/widgets/admin_settings_section.dart';
import 'package:kohera/features/rooms/widgets/invite_user_dialog.dart';
import 'package:kohera/features/rooms/widgets/room_members_section.dart';
import 'package:kohera/shared/widgets/avatar_edit_overlay.dart';
import 'package:kohera/shared/widgets/detail_action_button.dart';
import 'package:kohera/shared/widgets/joined_member_count.dart';
import 'package:provider/provider.dart';
/// Displays room details: header, actions, members, encryption,
/// media gallery, notification settings, and admin controls.
///
/// SDK-free: all data and SDK actions are provided by [RoomDetailsController],
/// the conversion boundary that owns the `Room`. The panel only depends on
/// Kohera domain models and callbacks.
///
/// When [isFullPage] is true, wraps itself in a Scaffold with an AppBar
/// (for mobile/tablet push route). Otherwise renders as a bare panel
/// (for the desktop side panel).
class RoomDetailsPanel extends StatefulWidget {
  const RoomDetailsPanel({
    required this.roomId,
    super.key,
    this.isFullPage = false,
  });

  final String roomId;
  final bool isFullPage;

  @override
  State<RoomDetailsPanel> createState() => _RoomDetailsPanelState();
}

class _RoomDetailsPanelState extends State<RoomDetailsPanel> {
  late RoomDetailsController _controller;
  final Set<String> _inFlight = {};
  String? _error;
  bool _deviceKeysExpanded = false;
  bool _created = false;

  bool get _loading => _inFlight.isNotEmpty;
  bool _busy(String action) => _inFlight.contains(action);

  // ── Lifecycle ───────────────────────────────────────────────

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_created) {
      _created = true;
      _controller = RoomDetailsController(
        roomId: widget.roomId,
        matrix: context.read<MatrixService>(),
        selection: context.read<SelectionService>(),
      )..addListener(_onChanged);
      _controller.init();
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(RoomDetailsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.checkRoomChanged();
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────

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

  Future<void> _showInviteDialog() async {
    final result =
        await InviteUserDialog.show(context, params: _controller.inviteDialogParams());
    if (result == null || !mounted) return;

    final scaffold = ScaffoldMessenger.of(context);
    await _run('invite', () async {
      await _controller.invite(result);
      scaffold.showSnackBar(
        SnackBar(content: Text('Invited $result')),
      );
    });
  }

  Future<void> _confirmLeave() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Leave room?',
      message: 'You will leave "${_controller.summary?.displayname ?? widget.roomId}".',
      confirmLabel: 'Leave',
      destructive: true,
    );

    if (!confirmed || !mounted) return;

    final navigator = Navigator.of(context);
    await _run('leave', () async {
      await _controller.leave();
      if (mounted && widget.isFullPage) navigator.pop();
    });
  }

  Future<void> _setPushRule(KoheraPushRuleState state) =>
      _run('pushRule', () => _controller.setPushRule(state));

  Future<void> _verifyDevice(KoheraDeviceKey dk) async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await _controller.verifyDevice(context, dk.deviceId);
    } catch (e) {
      debugPrint('[Kohera] Failed to start verification: $e');
      if (mounted) {
        scaffold.showSnackBar(
          const SnackBar(content: Text('Failed to start verification')),
        );
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (!_controller.hasRoom) {
      final body = Center(child: Text('Room not found', style: tt.bodyLarge));
      return widget.isFullPage ? Scaffold(appBar: AppBar(), body: body) : body;
    }

    final content = _buildContent(cs, tt);

    if (widget.isFullPage) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(KIcons.arrowBack),
            onPressed: () => context.popOrGo(
              Routes.room,
              pathParameters: {RouteParams.roomId: widget.roomId},
            ),
          ),
          title: Text(_controller.summary!.displayname),
        ),
        body: content,
      );
    }

    return Material(
      color: cs.surface,
      child: content,
    );
  }

  Widget _buildContent(ColorScheme cs, TextTheme tt) {
    final permissions = _controller.permissions;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (_loading) const LinearProgressIndicator(),
        _buildHeader(cs, tt),
        const Divider(),
        _buildActionsRow(cs),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
          ),
        const Divider(),
        _controller.buildJoinAccessSection(),
        const Divider(),
        if (_controller.memberList != null)
          RoomMembersSection(
            members: _controller.memberList!,
            onMemberTap: (member) => _controller.showMemberSheet(context, member),
            avatarResolver: _controller.avatarResolver,
            presence: _controller.presence,
          ),
        const Divider(),
        _buildEncryptionSection(cs, tt),
        const Divider(),
        _controller.buildSharedMediaSection(),
        const Divider(),
        _buildNotificationSection(cs, tt),
        if (permissions != null &&
            (permissions.canEditName ||
                permissions.canEditTopic ||
                permissions.canEnableEncryption ||
                permissions.canChangePowerLevels)) ...[
          const Divider(),
          AdminSettingsSection(
            permissions: permissions,
            onSaveName: _controller.setName,
            onSaveTopic: _controller.setDescription,
            onEnableEncryption: _controller.enableEncryption,
          ),
        ],
      ],
    );
  }

  // ── Header ─────────────────────────────────────────────────

  Widget _buildHeader(ColorScheme cs, TextTheme tt) {
    final summary = _controller.summary!;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          AvatarEditOverlay(
            roomId: _controller.roomId,
            summary: summary,
            canEditAvatar: _controller.permissions?.canEditAvatar ?? false,
            avatarResolver: _controller.avatarResolver,
            onSetAvatar: _controller.setAvatar,
          ),
          const SizedBox(height: 12),
          Text(
            summary.displayname,
            style: tt.titleLarge,
            textAlign: TextAlign.center,
          ),
          if (summary.topic != null && summary.topic!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              summary.topic!,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 4),
          JoinedMemberCount(
            roomId: _controller.roomId,
            summaryMemberCount: _controller.summaryMemberCount ?? 0,
            participantListComplete: _controller.participantListComplete,
            resolveMemberCount: _controller.resolveMemberCount,
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

  Widget _buildActionsRow(ColorScheme cs) {
    final isMuted = _controller.isMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          DetailActionButton(
            icon: isMuted ? KIcons.notificationsOffOutlined : KIcons.notificationsOutlined,
            label: isMuted ? 'Unmute' : 'Mute',
            onTap: _busy('mute') ? null : () => _run('mute', _controller.toggleMute),
          ),
          DetailActionButton(
            icon: _controller.isFavourite ? KIcons.starRounded : KIcons.starBorderRounded,
            label: _controller.isFavourite ? 'Starred' : 'Star',
            onTap: _busy('favourite') ? null : () => _run('favourite', _controller.toggleFavourite),
          ),
          DetailActionButton(
            icon: KIcons.personAddOutlined,
            label: 'Invite',
            onTap: _busy('invite') ? null : _showInviteDialog,
          ),
          DetailActionButton(
            icon: KIcons.exitToAppRounded,
            label: 'Leave',
            color: cs.error,
            onTap: _busy('leave') ? null : _confirmLeave,
          ),
        ],
      ),
    );
  }

  // ── Encryption section ─────────────────────────────────────

  Widget _buildEncryptionSection(ColorScheme cs, TextTheme tt) {
    final encrypted = _controller.encrypted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Icon(
            encrypted ? KIcons.lockRounded : KIcons.lockOpenRounded,
            color: encrypted ? cs.primary : cs.onSurfaceVariant,
          ),
          title: Text(encrypted ? 'Encrypted' : 'Not encrypted'),
          subtitle: Text(
            encrypted
                ? 'Messages are end-to-end encrypted'
                : 'Messages are not encrypted',
            style: tt.bodySmall,
          ),
        ),
        if (encrypted && _controller.isDirectChat)
          _buildDeviceVerificationSection(cs, tt),
      ],
    );
  }

  Widget _buildDeviceVerificationSection(ColorScheme cs, TextTheme tt) {
    if (_controller.partnerId == null) return const SizedBox.shrink();

    final devices = _controller.deviceKeys;
    if (devices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Text(
          'No device keys available',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    final verified = devices.where((d) => d.verified).length;
    final total = devices.length;
    final allVerified = verified == total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          leading: Icon(
            allVerified ? KIcons.verified : KIcons.shieldOutlined,
            color: allVerified ? cs.primary : cs.onSurfaceVariant,
            size: 20,
          ),
          title: Text(
            '$verified of $total device${total == 1 ? '' : 's'} verified',
            style: tt.bodyMedium,
          ),
          trailing: Icon(
            _deviceKeysExpanded ? KIcons.expandLess : KIcons.expandMore,
          ),
          onTap: () => setState(() => _deviceKeysExpanded = !_deviceKeysExpanded),
        ),
        if (_deviceKeysExpanded)
          ...devices.map((dk) => _buildDeviceKeyTile(dk, cs, tt)),
      ],
    );
  }

  Widget _buildDeviceKeyTile(KoheraDeviceKey dk, ColorScheme cs, TextTheme tt) {
    final IconData icon;
    final String label;
    final Color color;
    if (dk.blocked) {
      icon = KIcons.block;
      label = 'Blocked';
      color = cs.error;
    } else if (dk.verified) {
      icon = KIcons.verified;
      label = 'Verified';
      color = cs.primary;
    } else {
      icon = KIcons.shieldOutlined;
      label = 'Unverified';
      color = cs.onSurfaceVariant;
    }

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 56, right: 16),
      leading: Icon(KIcons.devices, size: 18, color: cs.onSurfaceVariant),
      title: Text(
        dk.displayName ?? dk.deviceId ?? 'Unknown device',
        style: tt.bodySmall,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: tt.labelSmall?.copyWith(color: color)),
        ],
      ),
      trailing: !dk.verified && !dk.blocked
          ? TextButton(
              onPressed: () => _verifyDevice(dk),
              child: const Text('Verify'),
            )
          : null,
    );
  }

  // ── Notification settings ──────────────────────────────────

  Widget _buildNotificationSection(ColorScheme cs, TextTheme tt) {
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
        RadioGroup<KoheraPushRuleState>(
          groupValue: _controller.pushRuleState,
          onChanged: _busy('pushRule') ? (_) {} : (v) => _setPushRule(v!),
          child: const Column(
            children: [
              RadioListTile<KoheraPushRuleState>(
                title: Text('All messages'),
                value: KoheraPushRuleState.notify,
              ),
              RadioListTile<KoheraPushRuleState>(
                title: Text('Mentions only'),
                value: KoheraPushRuleState.mentionsOnly,
              ),
              RadioListTile<KoheraPushRuleState>(
                title: Text('Muted'),
                value: KoheraPushRuleState.dontNotify,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
