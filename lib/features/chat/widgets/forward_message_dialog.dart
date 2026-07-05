import 'package:flutter/material.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/rooms/models/kohera_room_summary.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/room_avatar.dart';

// ── Forward message dialog ───────────────────────────────────────

class ForwardMessageDialog extends StatefulWidget {
  const ForwardMessageDialog._({
    required this.targets,
    required this.avatarResolver,
    required this.onForward,
  });

  final List<KoheraRoomSummary> targets;
  final AvatarResolver avatarResolver;
  final Future<void> Function(String roomId) onForward;

  static Future<void> show(
    BuildContext context, {
    required List<KoheraRoomSummary> targets,
    required AvatarResolver avatarResolver,
    required Future<void> Function(String roomId) onForward,
  }) {
    return showDialog(
      context: context,
      builder: (_) => ForwardMessageDialog._(
        targets: targets,
        avatarResolver: avatarResolver,
        onForward: onForward,
      ),
    );
  }

  @override
  State<ForwardMessageDialog> createState() => _ForwardMessageDialogState();
}

class _ForwardMessageDialogState extends State<ForwardMessageDialog> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _sending = false;

  late final List<KoheraRoomSummary> _targets;

  @override
  void initState() {
    super.initState();
    _targets = [...widget.targets]
      ..sort(
        (a, b) => a.displayname.toLowerCase().compareTo(
              b.displayname.toLowerCase(),
            ),
      );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _forwardTo(KoheraRoomSummary target) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await widget.onForward(target.roomId);
    } catch (e) {
      debugPrint('[Kohera] Failed to forward message: $e');
      if (!mounted) return;
      setState(() => _sending = false);
      context.showSnack(
        'Failed to forward: ${MatrixService.friendlyAuthError(e)}',
      );
      return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final name = target.displayname;
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(content: Text('Forwarded to $name')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? _targets
        : _targets
            .where(
              (t) => t.displayname.toLowerCase().contains(
                    _query.toLowerCase(),
                  ),
            )
            .toList();

    return AlertDialog(
      title: const Text('Forward to'),
      content: SizedBox(
        width: 400,
        height: 400,
        child: _targets.isEmpty
            ? const Center(child: Text('You have no rooms to forward to.'))
            : Column(
                children: [
                  TextField(
                    controller: _searchController,
                    autofocus: true,
                    enabled: !_sending,
                    decoration: const InputDecoration(
                      labelText: 'Search rooms',
                      prefixIcon: Icon(Icons.search_rounded),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No matching rooms.'))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final room = filtered[index];
                              return ListTile(
                                enabled: !_sending,
                                leading: RoomAvatarWidget(
                                  avatarUrl: room.avatarUrl,
                                  displayname: room.displayname,
                                  avatarResolver: widget.avatarResolver,
                                  size: 36,
                                ),
                                title: Text(
                                  room.displayname,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => _forwardTo(room),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
