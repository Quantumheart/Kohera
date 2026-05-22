import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/rooms/services/power_level_service.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

/// Full-page permissions screen reachable from the room admin settings.
///
/// Displays a "Who can…" section where each row maps to one or more
/// `m.room.power_levels` fields. Changes are written immediately via
/// [PowerLevelService.update].
class RoomPermissionsScreen extends StatelessWidget {
  const RoomPermissionsScreen({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context) {
    final room =
        context.read<MatrixService>().client.getRoomById(roomId);
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Permissions')),
        body: const Center(child: Text('Room not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Permissions')),
      body: ListView(
        children: [_WhoCanSection(room: room)],
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
          currentLevel: _scalar(content, 'invite', 0),
          canEdit: canEdit,
          onChanged: (v) => PowerLevelService.update(
            room,
            PowerLevelPatch(invite: v),
          ),
        ),
        _WhoCanRow(
          label: 'Send messages',
          currentLevel: _scalar(content, 'events_default', 0),
          canEdit: canEdit,
          onChanged: (v) => PowerLevelService.update(
            room,
            PowerLevelPatch(eventsDefault: v),
          ),
        ),
        _WhoCanRow(
          label: 'Change room name & topic',
          currentLevel: _event(content, EventTypes.RoomName,
              _scalar(content, 'state_default', 50),),
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
          currentLevel: _event(content, EventTypes.RoomAvatar,
              _scalar(content, 'state_default', 50),),
          canEdit: canEdit,
          onChanged: (v) => PowerLevelService.update(
            room,
            PowerLevelPatch(events: {EventTypes.RoomAvatar: v}),
          ),
        ),
        _WhoCanRow(
          label: 'Pin messages',
          currentLevel: _event(content, 'm.room.pinned_events',
              _scalar(content, 'state_default', 50),),
          canEdit: canEdit,
          onChanged: (v) => PowerLevelService.update(
            room,
            PowerLevelPatch(events: {'m.room.pinned_events': v}),
          ),
        ),
        _WhoCanRow(
          label: "Redact others' messages",
          currentLevel: _scalar(content, 'redact', 50),
          canEdit: canEdit,
          onChanged: (v) => PowerLevelService.update(
            room,
            PowerLevelPatch(redact: v),
          ),
        ),
        _WhoCanRow(
          label: 'Mention @room',
          currentLevel: _notification(content, 'room', 50),
          canEdit: canEdit,
          onChanged: (v) => PowerLevelService.update(
            room,
            PowerLevelPatch(notifications: {'room': v}),
          ),
        ),
        _WhoCanRow(
          label: 'Kick members',
          currentLevel: _scalar(content, 'kick', 50),
          canEdit: canEdit,
          onChanged: (v) => PowerLevelService.update(
            room,
            PowerLevelPatch(kick: v),
          ),
        ),
        _WhoCanRow(
          label: 'Ban members',
          currentLevel: _scalar(content, 'ban', 50),
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

  static int _scalar(Map<String, Object?> c, String key, int fallback) =>
      c.tryGet<int>(key) ?? fallback;

  static int _event(
      Map<String, Object?> c, String eventType, int fallback,) {
    final events = c.tryGetMap<String, Object?>('events') ?? {};
    return events.tryGet<int>(eventType) ?? fallback;
  }

  static int _notification(
      Map<String, Object?> c, String key, int fallback,) {
    final notifs = c.tryGetMap<String, Object?>('notifications') ?? {};
    return notifs.tryGet<int>(key) ?? fallback;
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
