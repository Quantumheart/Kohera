import 'package:flutter/material.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/features/rooms/models/kohera_room_summary.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/loading_button_child.dart';
import 'package:kohera/shared/widgets/room_avatar.dart';

// ── Add Existing Rooms to Space Dialog ───────────────────────────

class AddExistingRoomsDialog extends StatefulWidget {
  const AddExistingRoomsDialog._({
    required this.candidateRooms,
    required this.existingChildIds,
    required this.avatarResolver,
    required this.onAddRooms,
  });

  /// Joined rooms (as SDK-free summaries) the user may add. The dialog filters
  /// out spaces and rooms already in the space.
  final List<KoheraRoomSummary> candidateRooms;

  /// Room IDs already children of the space (excluded from the list).
  final Set<String> existingChildIds;

  /// Resolves candidate avatar URIs to HTTP thumbnails.
  final AvatarResolver? avatarResolver;

  /// Adds the selected room IDs to the space. Returns the number of rooms that
  /// failed to add (0 = success). The parent performs the SDK `setSpaceChild`
  /// calls and invalidates the space tree.
  final Future<int> Function(List<String> roomIds) onAddRooms;

  static Future<void> show(
    BuildContext context, {
    required List<KoheraRoomSummary> candidateRooms,
    required Set<String> existingChildIds,
    required AvatarResolver? avatarResolver,
    required Future<int> Function(List<String> roomIds) onAddRooms,
  }) {
    return showDialog(
      context: context,
      builder: (_) => AddExistingRoomsDialog._(
        candidateRooms: candidateRooms,
        existingChildIds: existingChildIds,
        avatarResolver: avatarResolver,
        onAddRooms: onAddRooms,
      ),
    );
  }

  @override
  State<AddExistingRoomsDialog> createState() => _AddExistingRoomsDialogState();
}

class _AddExistingRoomsDialogState extends State<AddExistingRoomsDialog> {
  final _searchController = TextEditingController();
  final Set<String> _selected = {};
  bool _loading = false;
  String _query = '';
  late List<KoheraRoomSummary> _eligibleRooms;

  @override
  void initState() {
    super.initState();
    _eligibleRooms = _computeEligibleRooms();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<KoheraRoomSummary> _computeEligibleRooms() {
    return widget.candidateRooms
        .where((r) => !r.isSpace && !widget.existingChildIds.contains(r.roomId))
        .toList()
      ..sort(
        (a, b) => a.displayname.toLowerCase().compareTo(b.displayname.toLowerCase()),
      );
  }

  Future<void> _submit() async {
    if (_selected.isEmpty) return;

    setState(() => _loading = true);

    final failures = await widget.onAddRooms(_selected.toList());

    if (!mounted) return;

    if (failures > 0) {
      context.showSnack('Failed to add $failures room(s)');
      setState(() => _loading = false);
      return;
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? _eligibleRooms
        : _eligibleRooms
            .where(
              (r) => r.displayname.toLowerCase().contains(_query.toLowerCase()),
            )
            .toList();

    return AlertDialog(
      title: const Text('Add existing rooms'),
      content: SizedBox(
        width: 400,
        height: 400,
        child: _eligibleRooms.isEmpty
            ? const Center(
                child: Text('All your rooms are already in this space.'),
              )
            : Column(
                children: [
                  TextField(
                    controller: _searchController,
                    autofocus: true,
                    enabled: !_loading,
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
                              final checked = _selected.contains(room.roomId);
                              return CheckboxListTile(
                                value: checked,
                                onChanged: _loading
                                    ? null
                                    : (v) => setState(() {
                                          if (v == true) {
                                            _selected.add(room.roomId);
                                          } else {
                                            _selected.remove(room.roomId);
                                          }
                                        }),
                                secondary: RoomAvatarWidget(
                                  avatarUrl: room.avatarUrl,
                                  displayname: room.displayname,
                                  avatarResolver: widget.avatarResolver,
                                  size: 36,
                                ),
                                title: Text(
                                  room.displayname,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (_eligibleRooms.isNotEmpty)
          FilledButton(
            onPressed: _loading || _selected.isEmpty ? null : _submit,
            child: LoadingButtonChild(
              loading: _loading,
              child: Text('Add (${_selected.length})'),
            ),
          ),
      ],
    );
  }
}
