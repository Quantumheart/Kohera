import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/rooms/services/power_level_service.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

/// Full-page permissions screen reachable from the room admin settings.
///
/// Displays a "Roles" summary section followed by a "Who can…" section where
/// each row maps to one or more `m.room.power_levels` fields. Changes are
/// written immediately via [PowerLevelService.update].
///
/// Subscribes to the sync stream and rebuilds when power levels, join rules,
/// or encryption state change so a concurrent admin's edits appear live.
class RoomPermissionsScreen extends StatefulWidget {
  const RoomPermissionsScreen({required this.roomId, super.key});

  final String roomId;

  @override
  State<RoomPermissionsScreen> createState() => _RoomPermissionsScreenState();
}

class _RoomPermissionsScreenState extends State<RoomPermissionsScreen> {
  StreamSubscription<SyncUpdate>? _syncSub;
  Timer? _debounce;

  static const Set<String> _watchedTypes = {
    EventTypes.RoomPowerLevels,
    EventTypes.RoomJoinRules,
    EventTypes.Encryption,
  };

  @override
  void initState() {
    super.initState();
    final client = context.read<MatrixService>().client;
    _syncSub = client.onSync.stream.listen(_onSync);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    unawaited(_syncSub?.cancel());
    super.dispose();
  }

  void _onSync(SyncUpdate update) {
    final stateEvents =
        update.rooms?.join?[widget.roomId]?.state ?? [];
    if (!stateEvents.any((e) => _watchedTypes.contains(e.type))) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final room =
        context.read<MatrixService>().client.getRoomById(widget.roomId);
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Permissions')),
        body: const Center(child: Text('Room not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Permissions')),
      body: ListView(
        children: [
          _RolesSection(room: room),
          _WhoCanSection(room: room),
          _DangerZoneSection(room: room),
          _AdvancedSection(room: room),
        ],
      ),
    );
  }
}

// ── Shared power-level helpers ─────────────────────────────────

int _plScalar(Map<String, Object?> c, String key, int fallback) =>
    c.tryGet<int>(key) ?? fallback;

int _plEvent(Map<String, Object?> c, String eventType, int fallback) {
  final events = c.tryGetMap<String, Object?>('events') ?? {};
  return events.tryGet<int>(eventType) ?? fallback;
}

int _plNotification(Map<String, Object?> c, String key, int fallback) {
  final notifs = c.tryGetMap<String, Object?>('notifications') ?? {};
  return notifs.tryGet<int>(key) ?? fallback;
}

/// Returns the plain-English list of things a user at [level] can do,
/// given the current [content] of the `m.room.power_levels` event.
List<String> plCapabilities(int level, Map<String, Object?> content) {
  final stateDefault = _plScalar(content, 'state_default', 50);
  return [
    if (level >= _plScalar(content, 'events_default', 0)) 'Send messages',
    if (level >= _plScalar(content, 'invite', 0)) 'Invite people',
    if (level >= _plNotification(content, 'room', 50)) 'Mention @room',
    if (level >= _plScalar(content, 'redact', 50)) "Redact others' messages",
    if (level >= _plEvent(content, EventTypes.RoomName, stateDefault))
      'Change room name & topic',
    if (level >= _plEvent(content, EventTypes.RoomAvatar, stateDefault))
      'Change room avatar',
    if (level >= _plEvent(content, 'm.room.pinned_events', stateDefault))
      'Pin messages',
    if (level >= _plScalar(content, 'kick', 50)) 'Kick members',
    if (level >= _plScalar(content, 'ban', 50)) 'Ban & unban members',
    if (level >= _plEvent(content, EventTypes.RoomPowerLevels, stateDefault))
      'Change permissions',
  ];
}

// ── Roles section ──────────────────────────────────────────────

class _RolesSection extends StatelessWidget {
  const _RolesSection({required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final content =
        room.getState(EventTypes.RoomPowerLevels)?.content ?? {};
    final participants = room.getParticipants();

    int countAt(bool Function(int) test) => participants
        .where((u) => test(room.getPowerLevelByUserId(u.id)))
        .length;

    final adminCount = countAt((pl) => pl >= 100);
    final modCount = countAt((pl) => pl >= 50 && pl < 100);
    final memberCount = countAt((pl) => pl < 50);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'ROLES',
            style: tt.labelSmall?.copyWith(
              color: cs.primary,
              letterSpacing: 1.5,
            ),
          ),
        ),
        _RoleCard(
          label: 'Admin',
          description: 'Full control over the room',
          icon: Icons.admin_panel_settings_outlined,
          level: 100,
          memberCount: adminCount,
          content: content,
        ),
        _RoleCard(
          label: 'Moderator',
          description: 'Can manage messages and members',
          icon: Icons.shield_outlined,
          level: 50,
          memberCount: modCount,
          content: content,
        ),
        _RoleCard(
          label: 'Member',
          description: 'Standard room participant',
          icon: Icons.person_outline,
          level: 0,
          memberCount: memberCount,
          content: content,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _RoleCard extends StatefulWidget {
  const _RoleCard({
    required this.label,
    required this.description,
    required this.icon,
    required this.level,
    required this.memberCount,
    required this.content,
  });

  final String label;
  final String description;
  final IconData icon;
  final int level;
  final int memberCount;
  final Map<String, Object?> content;

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final caps = plCapabilities(widget.level, widget.content);
    final countLabel =
        '${widget.memberCount} ${widget.memberCount == 1 ? 'member' : 'members'}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(widget.icon, color: cs.primary, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.label, style: tt.titleSmall),
                          Text(
                            widget.description,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      countLabel,
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.expand_more, size: 20),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: _expanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(height: 1, color: cs.outlineVariant),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text(
                            'What a ${widget.label.toLowerCase()} can do:',
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (caps.isEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Text(
                              'No special permissions at this level.',
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          )
                        else
                          for (final cap in caps)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.check_circle_outline,
                                    size: 14,
                                    color: cs.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(cap, style: tt.bodySmall),
                                ],
                              ),
                            ),
                        const SizedBox(height: 10),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Who can… section ──────────────────────────────────────────

class _WhoCanSection extends StatelessWidget {
  const _WhoCanSection({required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final content =
        room.getState(EventTypes.RoomPowerLevels)?.content ?? {};
    final canEdit = room.canChangePowerLevel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'WHO CAN…',
            style: tt.labelSmall?.copyWith(
              color: cs.primary,
              letterSpacing: 1.5,
            ),
          ),
        ),
        _WhoCanRow(
          label: 'Invite people',
          currentLevel: _plScalar(content, 'invite', 0),
          canEdit: canEdit,
          onChanged: (v) => PowerLevelService.update(
            room,
            PowerLevelPatch(invite: v),
          ),
        ),
        _WhoCanRow(
          label: 'Send messages',
          currentLevel: _plScalar(content, 'events_default', 0),
          canEdit: canEdit,
          onChanged: (v) => PowerLevelService.update(
            room,
            PowerLevelPatch(eventsDefault: v),
          ),
        ),
        _WhoCanRow(
          label: 'Change room name & topic',
          currentLevel: _plEvent(content, EventTypes.RoomName,
              _plScalar(content, 'state_default', 50),),
          canEdit: canEdit,
          onChanged: (v) => PowerLevelService.update(
            room,
            PowerLevelPatch(events: {
              EventTypes.RoomName: v,
              EventTypes.RoomTopic: v,
            },),
          ),
        ),
        _WhoCanRow(
          label: 'Change room avatar',
          currentLevel: _plEvent(content, EventTypes.RoomAvatar,
              _plScalar(content, 'state_default', 50),),
          canEdit: canEdit,
          onChanged: (v) => PowerLevelService.update(
            room,
            PowerLevelPatch(events: {EventTypes.RoomAvatar: v}),
          ),
        ),
        _WhoCanRow(
          label: 'Pin messages',
          currentLevel: _plEvent(content, 'm.room.pinned_events',
              _plScalar(content, 'state_default', 50),),
          canEdit: canEdit,
          onChanged: (v) => PowerLevelService.update(
            room,
            PowerLevelPatch(events: {'m.room.pinned_events': v}),
          ),
        ),
        _WhoCanRow(
          label: "Redact others' messages",
          currentLevel: _plScalar(content, 'redact', 50),
          canEdit: canEdit,
          onChanged: (v) => PowerLevelService.update(
            room,
            PowerLevelPatch(redact: v),
          ),
        ),
        _WhoCanRow(
          label: 'Mention @room',
          currentLevel: _plNotification(content, 'room', 50),
          canEdit: canEdit,
          onChanged: (v) => PowerLevelService.update(
            room,
            PowerLevelPatch(notifications: {'room': v}),
          ),
        ),
        _WhoCanRow(
          label: 'Kick members',
          currentLevel: _plScalar(content, 'kick', 50),
          canEdit: canEdit,
          onChanged: (v) => PowerLevelService.update(
            room,
            PowerLevelPatch(kick: v),
          ),
        ),
        _WhoCanRow(
          label: 'Ban members',
          currentLevel: _plScalar(content, 'ban', 50),
          canEdit: canEdit,
          onChanged: (v) => PowerLevelService.update(
            room,
            PowerLevelPatch(ban: v),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── Individual row ────────────────────────────────────────────

class _WhoCanRow extends StatefulWidget {
  const _WhoCanRow({
    required this.label,
    required this.currentLevel,
    required this.canEdit,
    required this.onChanged,
  });

  final String label;
  final int currentLevel;
  final bool canEdit;
  final Future<void> Function(int) onChanged;

  @override
  State<_WhoCanRow> createState() => _WhoCanRowState();
}

class _WhoCanRowState extends State<_WhoCanRow> {
  bool _loading = false;
  String? _error;

  static const _presets = [0, 50, 100];

  String _label(int level) => switch (level) {
        0 => 'Everyone',
        50 => 'Moderators+',
        100 => 'Admins only',
        _ => 'Custom ($level)',
      };

  Future<void> _handleChange(int newLevel) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.onChanged(newLevel);
    } on PowerLevelException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isCustom = !_presets.contains(widget.currentLevel);

    final items = <DropdownMenuItem<int>>[
      if (isCustom)
        DropdownMenuItem(
          value: widget.currentLevel,
          child: Text(_label(widget.currentLevel)),
        ),
      for (final level in _presets)
        DropdownMenuItem(
          value: level,
          child: Text(_label(level)),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.label, style: tt.bodyMedium),
              ),
              if (_loading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                DropdownButton<int>(
                  value: widget.currentLevel,
                  isDense: true,
                  onChanged: widget.canEdit && !_loading
                      ? (v) {
                          if (v != null && v != widget.currentLevel) {
                            unawaited(_handleChange(v));
                          }
                        }
                      : null,
                  items: items,
                ),
            ],
          ),
          if (_error != null)
            Text(
              _error!,
              style: tt.bodySmall?.copyWith(color: cs.error),
            ),
        ],
      ),
    );
  }
}

// ── Danger zone section ───────────────────────────────────────

Future<bool> _confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  bool isDestructive = false,
}) async {
  final cs = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: isDestructive
              ? FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

class _DangerZoneSection extends StatefulWidget {
  const _DangerZoneSection({required this.room});

  final Room room;

  @override
  State<_DangerZoneSection> createState() => _DangerZoneSectionState();
}

class _DangerZoneSectionState extends State<_DangerZoneSection> {
  bool _joinRulesLoading = false;
  bool _permLevelLoading = false;
  bool _encryptionLoading = false;
  String? _joinRulesError;
  String? _permLevelError;
  String? _encryptionError;

  static const _presets = [0, 50, 100];

  String _levelLabel(int level) => switch (level) {
        0 => 'Everyone',
        50 => 'Moderators+',
        100 => 'Admins only',
        _ => 'Custom ($level)',
      };

  String _joinRuleLabel(JoinRules rule) => switch (rule) {
        JoinRules.public => 'Public',
        JoinRules.invite => 'Invite-only',
        JoinRules.knock => 'Knock',
        JoinRules.restricted => 'Restricted',
        _ => rule.text,
      };

  String _joinRuleDescription(JoinRules rule) => switch (rule) {
        JoinRules.public =>
          'Anyone can join without an invitation. The room will be publicly discoverable.',
        JoinRules.invite => 'Only users invited by a member can join.',
        JoinRules.knock =>
          'Users can request to join. A moderator must approve each request.',
        JoinRules.restricted =>
          'Users in a linked space can join automatically.',
        _ => 'Change who can join this room.',
      };

  Future<void> _changeJoinRule(JoinRules newRule) async {
    final confirmed = await _confirmDialog(
      context,
      title: 'Change join rule to "${_joinRuleLabel(newRule)}"?',
      message: _joinRuleDescription(newRule),
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _joinRulesLoading = true;
      _joinRulesError = null;
    });
    try {
      await widget.room.setJoinRules(newRule);
    } catch (e) {
      if (mounted) setState(() => _joinRulesError = e.toString());
    } finally {
      if (mounted) setState(() => _joinRulesLoading = false);
    }
  }

  Future<void> _changePermLevel(int newLevel) async {
    final ownLevel = widget.room
        .getPowerLevelByUserId(widget.room.client.userID ?? '');
    final selfLockout = newLevel > ownLevel;
    final confirmed = await _confirmDialog(
      context,
      title: 'Change permissions requirement?',
      message: selfLockout
          ? 'Warning: setting this to "${_levelLabel(newLevel)}" will prevent '
              'you from changing permissions in the future since your own power '
              'level ($ownLevel) is below the new threshold.'
          : 'Only users at level $newLevel or above will be able to '
              'change room permissions.',
      isDestructive: selfLockout,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _permLevelLoading = true;
      _permLevelError = null;
    });
    try {
      await PowerLevelService.update(
        widget.room,
        PowerLevelPatch(events: {EventTypes.RoomPowerLevels: newLevel}),
      );
    } on PowerLevelException catch (e) {
      if (mounted) setState(() => _permLevelError = e.message);
    } catch (e) {
      if (mounted) setState(() => _permLevelError = e.toString());
    } finally {
      if (mounted) setState(() => _permLevelLoading = false);
    }
  }

  Future<void> _enableEncryption() async {
    final confirmed = await _confirmDialog(
      context,
      title: 'Enable encryption?',
      message: "This can't be undone. Once enabled, all future messages will "
          'be end-to-end encrypted and the room cannot be made unencrypted.',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _encryptionLoading = true;
      _encryptionError = null;
    });
    try {
      await widget.room.enableEncryption();
    } catch (e) {
      if (mounted) setState(() => _encryptionError = e.toString());
    } finally {
      if (mounted) setState(() => _encryptionLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final room = widget.room;
    final content =
        room.getState(EventTypes.RoomPowerLevels)?.content ?? {};
    final stateDefault = _plScalar(content, 'state_default', 50);
    final currentPermLevel =
        _plEvent(content, EventTypes.RoomPowerLevels, stateDefault);
    final currentJoinRule = room.joinRules;

    final canEditPermLevel = room.canChangePowerLevel;
    final canEditJoinRules = room.canChangeJoinRules;
    final canEnableEncryption =
        !room.encrypted && room.canChangeStateEvent(EventTypes.Encryption);

    // Hide the section entirely if there's nothing to show.
    if (!canEditPermLevel && !canEditJoinRules && !canEnableEncryption) {
      return const SizedBox.shrink();
    }

    final supportedRules = [
      JoinRules.public,
      JoinRules.invite,
      JoinRules.knock,
      if (currentJoinRule == JoinRules.restricted) JoinRules.restricted,
    ];

    final isCustomPermLevel = !_presets.contains(currentPermLevel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: cs.error),
              const SizedBox(width: 6),
              Text(
                'DANGER ZONE',
                style: tt.labelSmall?.copyWith(
                  color: cs.error,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),

        // ── Who can change permissions ─────────────────────────
        if (canEditPermLevel) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Who can change permissions',
                        style: tt.bodyMedium,
                      ),
                    ),
                    if (_permLevelLoading)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      DropdownButton<int>(
                        value: currentPermLevel,
                        isDense: true,
                        onChanged: (v) {
                          if (v != null && v != currentPermLevel) {
                            unawaited(_changePermLevel(v));
                          }
                        },
                        items: [
                          if (isCustomPermLevel)
                            DropdownMenuItem(
                              value: currentPermLevel,
                              child: Text(_levelLabel(currentPermLevel)),
                            ),
                          for (final level in _presets)
                            DropdownMenuItem(
                              value: level,
                              child: Text(_levelLabel(level)),
                            ),
                        ],
                      ),
                  ],
                ),
                if (_permLevelError != null)
                  Text(
                    _permLevelError!,
                    style: tt.bodySmall?.copyWith(color: cs.error),
                  ),
              ],
            ),
          ),
        ],

        // ── Join rule ──────────────────────────────────────────
        if (canEditJoinRules) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Who can join', style: tt.bodyMedium),
                    ),
                    if (_joinRulesLoading)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      DropdownButton<JoinRules>(
                        value: currentJoinRule,
                        isDense: true,
                        onChanged: (v) {
                          if (v != null && v != currentJoinRule) {
                            unawaited(_changeJoinRule(v));
                          }
                        },
                        items: [
                          for (final rule in supportedRules)
                            DropdownMenuItem(
                              value: rule,
                              child: Text(_joinRuleLabel(rule)),
                            ),
                        ],
                      ),
                  ],
                ),
                if (_joinRulesError != null)
                  Text(
                    _joinRulesError!,
                    style: tt.bodySmall?.copyWith(color: cs.error),
                  ),
              ],
            ),
          ),
        ],

        // ── Enable encryption ──────────────────────────────────
        if (canEnableEncryption)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Enable encryption', style: tt.bodyMedium),
                          Text(
                            'Irreversible — cannot be undone',
                            style: tt.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (_encryptionLoading)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.errorContainer,
                          foregroundColor: cs.onErrorContainer,
                        ),
                        onPressed: _enableEncryption,
                        child: const Text('Enable'),
                      ),
                  ],
                ),
                if (_encryptionError != null)
                  Text(
                    _encryptionError!,
                    style: tt.bodySmall?.copyWith(color: cs.error),
                  ),
              ],
            ),
          ),

        const SizedBox(height: 24),
      ],
    );
  }
}
// ── Advanced section ──────────────────────────────────────────

/// One row in the per-event-type editor: an event type string + integer level.
class _EventRowData {
  _EventRowData({required String type, required String level})
      : typeCtrl = TextEditingController(text: type),
        levelCtrl = TextEditingController(text: level);

  final TextEditingController typeCtrl;
  final TextEditingController levelCtrl;

  void dispose() {
    typeCtrl.dispose();
    levelCtrl.dispose();
  }
}

/// Collapsed-by-default section that exposes raw `m.room.power_levels` fields
/// (scalars + per-event-type map). Changes are applied atomically via a single
/// [setRoomStateWithKey] call so deletions are possible (PowerLevelService
/// never removes existing keys).
///
/// Hidden entirely when the local user cannot change power levels.
class _AdvancedSection extends StatefulWidget {
  const _AdvancedSection({required this.room});

  final Room room;

  @override
  State<_AdvancedSection> createState() => _AdvancedSectionState();
}

class _AdvancedSectionState extends State<_AdvancedSection> {
  bool _expanded = false;
  bool _saving = false;
  String? _error;

  late TextEditingController _usersDefaultCtrl;
  late TextEditingController _stateDefaultCtrl;
  late TextEditingController _eventsDefaultCtrl;
  final List<_EventRowData> _eventRows = [];

  Map<String, Object?> get _currentContent =>
      widget.room.getState(EventTypes.RoomPowerLevels)?.content ?? {};

  @override
  void initState() {
    super.initState();
    _initFromContent(_currentContent);
  }

  void _initFromContent(Map<String, Object?> c) {
    _usersDefaultCtrl = TextEditingController(
      text: _plScalar(c, 'users_default', 0).toString(),
    );
    _stateDefaultCtrl = TextEditingController(
      text: _plScalar(c, 'state_default', 50).toString(),
    );
    _eventsDefaultCtrl = TextEditingController(
      text: _plScalar(c, 'events_default', 0).toString(),
    );
    final events = c.tryGetMap<String, Object?>('events') ?? {};
    _eventRows
      ..clear()
      ..addAll(
        events.entries.map(
          (e) => _EventRowData(
            type: e.key,
            level: (e.value as int? ?? 0).toString(),
          ),
        ),
      );
  }

  @override
  void dispose() {
    _usersDefaultCtrl.dispose();
    _stateDefaultCtrl.dispose();
    _eventsDefaultCtrl.dispose();
    for (final r in _eventRows) {
      r.dispose();
    }
    super.dispose();
  }

  void _reset() {
    for (final r in _eventRows) {
      r.dispose();
    }
    _initFromContent(_currentContent);
    setState(() => _error = null);
  }

  /// Validates and returns a human-readable error, or null if clean.
  String? _validate() {
    for (final ctrl in [_usersDefaultCtrl, _stateDefaultCtrl, _eventsDefaultCtrl]) {
      if (int.tryParse(ctrl.text.trim()) == null) {
        return 'Scalar values must be integers.';
      }
    }
    final types = <String>[];
    for (final row in _eventRows) {
      final t = row.typeCtrl.text.trim();
      final l = row.levelCtrl.text.trim();
      if (t.isEmpty) return 'Event type cannot be empty.';
      if (int.tryParse(l) == null) return 'Level for "$t" must be an integer.';
      if (types.contains(t)) return 'Duplicate event type: "$t".';
      types.add(t);
    }
    return null;
  }

  Future<void> _apply() async {
    final validationError = _validate();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final content = _currentContent.copy();

      content['users_default'] = int.parse(_usersDefaultCtrl.text.trim());
      content['state_default'] = int.parse(_stateDefaultCtrl.text.trim());
      content['events_default'] = int.parse(_eventsDefaultCtrl.text.trim());

      final eventsMap = <String, Object?>{};
      for (final row in _eventRows) {
        eventsMap[row.typeCtrl.text.trim()] =
            int.parse(row.levelCtrl.text.trim());
      }
      content['events'] = eventsMap;

      await widget.room.client.setRoomStateWithKey(
        widget.room.id,
        EventTypes.RoomPowerLevels,
        '',
        content,
      );
    } on MatrixException catch (e) {
      if (mounted) setState(() => _error = e.errorMessage);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool get _isDirty {
    final c = _currentContent;
    if (_usersDefaultCtrl.text.trim() !=
        _plScalar(c, 'users_default', 0).toString()) {
      return true;
    }
    if (_stateDefaultCtrl.text.trim() !=
        _plScalar(c, 'state_default', 50).toString()) {
      return true;
    }
    if (_eventsDefaultCtrl.text.trim() !=
        _plScalar(c, 'events_default', 0).toString()) {
      return true;
    }
    final savedEvents = c.tryGetMap<String, Object?>('events') ?? {};
    if (_eventRows.length != savedEvents.length) return true;
    for (final row in _eventRows) {
      final t = row.typeCtrl.text.trim();
      final saved = savedEvents[t];
      if (saved == null) return true;
      if (row.levelCtrl.text.trim() != saved.toString()) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.room.canChangePowerLevel) return const SizedBox.shrink();

    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final validationError = _validate();
    final canApply = !_saving && _isDirty && validationError == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Text(
                  'ADVANCED',
                  style: tt.labelSmall?.copyWith(
                    color: cs.error,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more, size: 20, color: cs.error),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _expanded ? _buildBody(context, tt, cs, canApply, validationError) : const SizedBox.shrink(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    TextTheme tt,
    ColorScheme cs,
    bool canApply,
    String? validationError,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Warning banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: cs.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'These are raw power-level values. Incorrect settings can '
                    'lock everyone out of the room.',
                    style: tt.bodySmall
                        ?.copyWith(color: cs.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Scalar fields
          Text('Scalar defaults', style: tt.labelMedium),
          const SizedBox(height: 8),
          _ScalarField(
            label: 'users_default',
            controller: _usersDefaultCtrl,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          _ScalarField(
            label: 'state_default',
            controller: _stateDefaultCtrl,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          _ScalarField(
            label: 'events_default',
            controller: _eventsDefaultCtrl,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),

          // Per-event rows
          Row(
            children: [
              Text('Per-event overrides', style: tt.labelMedium),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
                onPressed: () => setState(() {
                  _eventRows.add(_EventRowData(type: '', level: '50'));
                }),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (int i = 0; i < _eventRows.length; i++)
            _EventRow(
              key: ObjectKey(_eventRows[i]),
              row: _eventRows[i],
              onChanged: () => setState(() {}),
              onRemove: () => setState(() {
                _eventRows[i].dispose();
                _eventRows.removeAt(i);
              }),
            ),

          // Validation or server error
          if (validationError != null && _isDirty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                validationError,
                style: tt.bodySmall?.copyWith(color: cs.error),
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: tt.bodySmall?.copyWith(color: cs.error),
              ),
            ),

          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : _reset,
                child: const Text('Reset'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: canApply ? _apply : null,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Apply'),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ScalarField extends StatelessWidget {
  const _ScalarField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'-?\d*')),
      ],
      onChanged: onChanged,
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.row,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final _EventRowData row;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: row.typeCtrl,
              decoration: const InputDecoration(
                labelText: 'Event type',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: row.levelCtrl,
              decoration: const InputDecoration(
                labelText: 'Level',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'-?\d*')),
              ],
              onChanged: (_) => onChanged(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: onRemove,
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}
