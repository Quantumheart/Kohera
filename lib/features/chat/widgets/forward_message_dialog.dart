import 'package:flutter/material.dart';
import 'package:kohera/shared/widgets/room_avatar.dart';
import 'package:matrix/matrix.dart';

// ── Forward Message Dialog ───────────────────────────────────────

class ForwardMessageDialog extends StatefulWidget {
  const ForwardMessageDialog._({required this.client});

  final Client client;

  static Future<Room?> show(
    BuildContext context, {
    required Client client,
  }) {
    return showDialog<Room>(
      context: context,
      builder: (_) => ForwardMessageDialog._(client: client),
    );
  }

  @override
  State<ForwardMessageDialog> createState() => _ForwardMessageDialogState();
}

class _ForwardMessageDialogState extends State<ForwardMessageDialog> {
  final _searchController = TextEditingController();
  String _query = '';
  late List<Room> _rooms;

  @override
  void initState() {
    super.initState();
    _rooms = _computeRooms();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Room> _computeRooms() {
    return widget.client.rooms
        .where((r) => r.membership == Membership.join && !r.isSpace)
        .toList()
      ..sort((a, b) => a
          .getLocalizedDisplayname()
          .toLowerCase()
          .compareTo(b.getLocalizedDisplayname().toLowerCase()),);
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
            ? const Center(child: Text('No rooms available.'))
            : Column(
                children: [
                  TextField(
                    controller: _searchController,
                    autofocus: true,
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
                                leading:
                                    RoomAvatarWidget(room: room, size: 36),
                                title: Text(
                                  room.getLocalizedDisplayname(),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => Navigator.pop(context, room),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
