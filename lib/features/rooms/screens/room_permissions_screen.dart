import 'dart:async';

import 'package:flutter/material.dart';
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
