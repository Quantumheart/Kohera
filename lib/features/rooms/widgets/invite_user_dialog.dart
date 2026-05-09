import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/utils/known_contacts.dart';
import 'package:matrix/matrix.dart' hide Visibility;

/// A reusable dialog that prompts for a Matrix user ID to invite to a room.
///
/// Returns the validated MXID string on success, or `null` if cancelled.
class InviteUserDialog extends StatefulWidget {
  const InviteUserDialog._({
    required this.room,
    required this.controller,
  });

  final Room room;
  final TextEditingController controller;

  /// Shows the invite dialog and returns the entered MXID, or `null`.
  static Future<String?> show(BuildContext context, {required Room room}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => InviteUserDialog._(room: room, controller: controller),
    ).whenComplete(controller.dispose);
  }

  @override
  State<InviteUserDialog> createState() => _InviteUserDialogState();
}

class _InviteUserDialogState extends State<InviteUserDialog> {
  static final _mxidRegex = RegExp(r'^@[^:]+:.+$');
  String? _error;
  bool _searching = false;
  List<Profile> _searchResults = [];
  Timer? _debounce;
  int _searchGeneration = 0;
  List<Profile>? _cachedContacts;
  Set<String>? _cachedMemberIds;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _debounce?.cancel();
    super.dispose();
  }

  // ── Suggestions data ────────────────────────────────────────

  Set<String> _memberIds() {
    return _cachedMemberIds ??= {
      for (final u in widget.room.getParticipants()) u.id,
    };
  }

  List<Profile> _knownContacts() {
    final members = _memberIds();
    return _cachedContacts ??= knownContacts(widget.room.client)
        .where((p) => !members.contains(p.userId))
        .toList();
  }

  // ── Search ──────────────────────────────────────────────────

  void _onTextChanged() {
    _debounce?.cancel();
    final query = widget.controller.text.trim();
    _searchGeneration++;
    if (query.isEmpty) {
      if (_searchResults.isNotEmpty || _searching) {
        setState(() {
          _searchResults = [];
          _searching = false;
        });
      } else {
        setState(() {});
      }
      return;
    }
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_searchDirectory(query));
    });
  }

  Future<void> _searchDirectory(String query) async {
    final gen = _searchGeneration;
    setState(() {
      _searching = true;
    });

    try {
      final response = await widget.room.client
          .searchUserDirectory(query, limit: 20);
      if (!mounted || gen != _searchGeneration) return;
      setState(() {
        _searchResults = response.results;
        _searching = false;
      });
    } catch (e) {
      debugPrint('[Kohera] Invite user search failed: $e');
      if (!mounted || gen != _searchGeneration) return;
      setState(() => _searching = false);
    }
  }

  // ── Submit ──────────────────────────────────────────────────

  void _submit([String? override]) {
    final mxid = (override ?? widget.controller.text).trim();
    if (mxid.isEmpty) {
      setState(() => _error = 'Please enter a Matrix ID');
      return;
    }
    if (!_mxidRegex.hasMatch(mxid)) {
      setState(() => _error = 'Invalid Matrix ID (use @user:server)');
      return;
    }
    Navigator.pop(context, mxid);
  }

  // ── Suggestion tiles ────────────────────────────────────────

  List<Widget> _suggestionTiles(ColorScheme cs) {
    final query = widget.controller.text.trim();
    final members = _memberIds();
    final List<Profile> profiles;
    if (query.isEmpty) {
      profiles = _knownContacts();
    } else {
      profiles = _searchResults
          .where((p) => !members.contains(p.userId))
          .toList();
    }
    if (profiles.isEmpty) return const [];

    final tiles = <Widget>[];
    if (query.isEmpty) {
      tiles.add(Padding(
        padding: const EdgeInsets.only(left: 4, top: 8, bottom: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Recent contacts',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),);
    }
    for (final p in profiles) {
      tiles.add(_SuggestionTile(profile: p, onTap: () => _submit(p.userId)));
    }
    return tiles;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tiles = _suggestionTiles(cs);

    return AlertDialog(
      title: const Text('Invite user'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: widget.controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Matrix ID',
                hintText: '@user:server.com',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(),
              ),
            if (tiles.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: tiles,
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(color: cs.error, fontSize: 13),
                  ),
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
        FilledButton(
          onPressed: _submit,
          child: const Text('Invite'),
        ),
      ],
    );
  }
}

// ── Suggestion tile ───────────────────────────────────────────

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.profile, required this.onTap});

  final Profile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = profile.displayName;
    final firstChar = (name ?? profile.userId).isNotEmpty
        ? (name ?? profile.userId).characters.first.toUpperCase()
        : '?';
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: cs.primaryContainer,
        child: Text(
          firstChar,
          style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13),
        ),
      ),
      title: Text(
        name ?? profile.userId,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: name != null
          ? Text(
              profile.userId,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            )
          : null,
      onTap: onTap,
    );
  }
}
