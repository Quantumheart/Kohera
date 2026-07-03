import 'package:flutter/material.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/features/rooms/models/kohera_room_summary.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/loading_button_child.dart';
import 'package:kohera/shared/widgets/room_avatar.dart';

// ── Add Room to Space Dialog ─────────────────────────────────────

class AddRoomToSpaceDialog extends StatefulWidget {
  const AddRoomToSpaceDialog._({
    required this.roomId,
    required this.candidateSpaces,
    required this.memberSpaceIds,
    required this.avatarResolver,
    required this.onAddToSpaces,
  });

  /// The room being added to spaces.
  final String roomId;

  /// Spaces the user may add the room to (parent pre-filters by permission),
  /// as SDK-free summaries. The dialog excludes those in [memberSpaceIds].
  final List<KoheraRoomSummary> candidateSpaces;

  /// Space IDs the room is already a child of (excluded from the list).
  final Set<String> memberSpaceIds;

  /// Resolves candidate avatar URIs to HTTP thumbnails.
  final AvatarResolver? avatarResolver;

  /// Adds the room to the selected spaces. Keys are selected space IDs, values
  /// are the per-space "suggested" flags. Returns the number of failures
  /// (0 = success). The parent performs the SDK `setSpaceChild` calls and
  /// invalidates the space tree.
  final Future<int> Function(Map<String, bool> selections) onAddToSpaces;

  static Future<void> show(
    BuildContext context, {
    required String roomId,
    required List<KoheraRoomSummary> candidateSpaces,
    required Set<String> memberSpaceIds,
    required AvatarResolver? avatarResolver,
    required Future<int> Function(Map<String, bool> selections) onAddToSpaces,
  }) {
    return showDialog(
      context: context,
      builder: (_) => AddRoomToSpaceDialog._(
        roomId: roomId,
        candidateSpaces: candidateSpaces,
        memberSpaceIds: memberSpaceIds,
        avatarResolver: avatarResolver,
        onAddToSpaces: onAddToSpaces,
      ),
    );
  }

  @override
  State<AddRoomToSpaceDialog> createState() => _AddRoomToSpaceDialogState();
}

class _AddRoomToSpaceDialogState extends State<AddRoomToSpaceDialog> {
  final Map<String, bool> _selected = {};
  final Map<String, bool> _suggested = {};
  bool _loading = false;

  List<KoheraRoomSummary> get _eligibleSpaces => widget.candidateSpaces
      .where((s) => !widget.memberSpaceIds.contains(s.roomId))
      .toList();

  bool get _hasSelection => _selected.values.any((v) => v);

  Future<void> _submit() async {
    final selections = Map<String, bool>.fromEntries(
      _selected.entries
          .where((e) => e.value)
          .map((e) => MapEntry(e.key, _suggested[e.key] == true)),
    );
    if (selections.isEmpty) return;

    setState(() => _loading = true);

    final failures = await widget.onAddToSpaces(selections);

    if (!mounted) return;

    if (failures > 0) {
      context.showSnack('Failed to add room to $failures space(s)');
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final eligible = _eligibleSpaces;

    return AlertDialog(
      title: const Text('Add to space'),
      content: SizedBox(
        width: 400,
        child: eligible.isEmpty
            ? const Text('This room is already in all your spaces.')
            : SizedBox(
                height: 400,
                child: ListView.builder(
                  itemCount: eligible.length,
                  itemBuilder: (context, index) {
                    final space = eligible[index];
                    final checked = _selected[space.roomId] == true;
                    return CheckboxListTile(
                      value: checked,
                      onChanged: _loading
                          ? null
                          : (v) => setState(
                              () => _selected[space.roomId] = v ?? false,
                            ),
                      secondary: RoomAvatarWidget(
                        avatarUrl: space.avatarUrl,
                        displayname: space.displayname,
                        avatarResolver: widget.avatarResolver,
                        size: 36,
                      ),
                      title: Text(
                        space.displayname,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Suggested'),
                          const SizedBox(width: 4),
                          SizedBox(
                            height: 24,
                            child: Switch(
                              value: _suggested[space.roomId] == true,
                              onChanged: checked && !_loading
                                  ? (v) => setState(
                                      () => _suggested[space.roomId] = v,
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (eligible.isNotEmpty)
          FilledButton(
            onPressed: _loading || !_hasSelection ? null : _submit,
            child: LoadingButtonChild(
              loading: _loading,
              child: const Text('Add'),
            ),
          ),
      ],
    );
  }
}
