import 'package:flutter/material.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/chat/services/message_forwarder.dart';
import 'package:kohera/shared/widgets/room_avatar.dart';
import 'package:matrix/matrix.dart' hide Visibility;

// ── Forward message dialog ───────────────────────────────────────

class ForwardMessageDialog extends StatefulWidget {
  const ForwardMessageDialog._({
    required this.event,
    required this.timeline,
    required this.matrixService,
  });

  final Event event;
  final Timeline? timeline;
  final MatrixService matrixService;

  static Future<void> show(
    BuildContext context, {
    required Event event,
    required Timeline? timeline,
    required MatrixService matrixService,
  }) {
    return showDialog(
      context: context,
      builder: (_) => ForwardMessageDialog._(
        event: event,
        timeline: timeline,
        matrixService: matrixService,
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
  late final List<Room> _rooms;

  @override
  void initState() {
    super.initState();
    _rooms = widget.matrixService.client.rooms
        .where((r) => r.membership == Membership.join && !r.isSpace)
        .toList()
      ..sort((a, b) => a
          .getLocalizedDisplayname()
          .toLowerCase()
          .compareTo(b.getLocalizedDisplayname().toLowerCase()),);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _forwardTo(Room room) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await MessageForwarder.forward(
        event: widget.event,
        target: room,
        timeline: widget.timeline,
      );
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
    final name = room.getLocalizedDisplayname();
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(content: Text('Forwarded to $name')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? _rooms
        : _rooms
            .where((r) => r
                .getLocalizedDisplayname()
                .toLowerCase()
                .contains(_query.toLowerCase()),)
            .toList();

    return AlertDialog(
      title: const Text('Forward to'),
      content: SizedBox(
        width: 400,
        height: 400,
        child: _rooms.isEmpty
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
                                leading:
                                    RoomAvatarWidget(
                                      avatarUrl: room.avatar?.toString(),
                                      displayname: room.getLocalizedDisplayname(),
                                      avatarResolver: widget.matrixService.avatarResolver,
                                      size: 36,
                                    ),
                                title: Text(
                                  room.getLocalizedDisplayname(),
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
