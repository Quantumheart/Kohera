import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:matrix/matrix.dart';

/// Admin settings for a room: edit name, topic, encryption,
/// and power levels. Only rendered when the user has sufficient power level.
class AdminSettingsSection extends StatefulWidget {
  const AdminSettingsSection({required this.room, super.key});

  final Room room;

  @override
  State<AdminSettingsSection> createState() => _AdminSettingsSectionState();
}

class _AdminSettingsSectionState extends State<AdminSettingsSection> {
  final _nameController = TextEditingController();
  final _topicController = TextEditingController();
  final Set<String> _inFlight = {};
  String? _error;
  String? _success;
  Timer? _successTimer;

  bool get _loading => _inFlight.isNotEmpty;
  bool _busy(String action) => _inFlight.contains(action);

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.room.getLocalizedDisplayname();
    _topicController.text = widget.room.topic;
  }

  @override
  void didUpdateWidget(AdminSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update controllers when room state changes via sync, but only if the
    // user hasn't edited the field (controller still matches old value).
    final newName = widget.room.getLocalizedDisplayname();
    final oldName = oldWidget.room.getLocalizedDisplayname();
    if (newName != oldName && _nameController.text == oldName) {
      _nameController.text = newName;
    }
    final newTopic = widget.room.topic;
    final oldTopic = oldWidget.room.topic;
    if (newTopic != oldTopic && _topicController.text == oldTopic) {
      _topicController.text = newTopic;
    }
  }

  @override
  void dispose() {
    _successTimer?.cancel();
    _nameController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _run(String action, Future<void> Function() task, {String? successMessage}) async {
    setState(() { _inFlight.add(action); _error = null; _success = null; });
    _successTimer?.cancel();
    try {
      await task();
      if (mounted && successMessage != null) {
        setState(() => _success = successMessage);
        _successTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _success = null);
        });
      }
    } catch (e) {
      debugPrint('[Kohera] $action failed: $e');
      if (mounted) setState(() => _error = MatrixService.friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _inFlight.remove(action));
    }
  }

  Future<void> _saveName() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) return;
    await _run('name', () => widget.room.setName(newName), successMessage: 'Room name updated');
  }

  Future<void> _saveTopic() async {
    final newTopic = _topicController.text.trim();
    await _run('topic', () => widget.room.setDescription(newTopic), successMessage: 'Topic updated');
  }

  Future<void> _enableEncryption() async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enable encryption?'),
        content: const Text(
          'This action is irreversible. Once encryption is enabled, '
          'it cannot be disabled.',
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
            child: const Text('Enable'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _run('encryption', () => widget.room.enableEncryption(), successMessage: 'Encryption enabled');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final room = widget.room;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
          child: Text(
            'ADMIN SETTINGS',
            style: tt.labelSmall?.copyWith(
              color: cs.primary,
              letterSpacing: 1.5,
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),

        // Room name
        if (room.canChangeStateEvent(EventTypes.RoomName))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    enabled: !_busy('name'),
                    decoration: const InputDecoration(
                      labelText: 'Room name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _busy('name') ? null : _saveName,
                  icon: const Icon(Icons.check_rounded),
                  tooltip: 'Save name',
                ),
              ],
            ),
          ),

        // Topic
        if (room.canChangeStateEvent(EventTypes.RoomTopic))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _topicController,
                    enabled: !_busy('topic'),
                    maxLines: 3,
                    minLines: 1,
                    decoration: const InputDecoration(
                      labelText: 'Topic',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _busy('topic') ? null : _saveTopic,
                  icon: const Icon(Icons.check_rounded),
                  tooltip: 'Save topic',
                ),
              ],
            ),
          ),

        // Enable encryption
        if (!room.encrypted &&
            room.canChangeStateEvent(EventTypes.Encryption))
          ListTile(
            leading: const Icon(Icons.lock_outline_rounded),
            title: const Text('Enable encryption'),
            subtitle: const Text('Irreversible'),
            trailing: FilledButton.tonal(
              onPressed: _busy('encryption') ? null : _enableEncryption,
              child: const Text('Enable'),
            ),
          ),

        // Permissions
        ListTile(
          leading: const Icon(Icons.admin_panel_settings_outlined),
          title: const Text('Permissions'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.goNamed(
            Routes.roomPermissions,
            pathParameters: {RouteParams.roomId: room.id},
          ),
        ),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
          ),
        if (_success != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_success!, style: TextStyle(color: cs.primary, fontSize: 13)),
          ),
      ],
    );
  }

}
