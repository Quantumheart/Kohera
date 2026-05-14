import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/utils/known_contacts.dart';
import 'package:matrix/matrix.dart' hide Visibility;

/// A reusable dialog that prompts for a Matrix user ID to invite to a room
/// or space. Suggests recent contacts and searches the homeserver's user
/// directory as the user types.
///
/// Returns the validated MXID string on success, or `null` if cancelled.
class InviteUserDialog extends StatefulWidget {
  const InviteUserDialog._({required this.room});

  final Room room;

  static Future<String?> show(BuildContext context, {required Room room}) {
    return showDialog<String>(
      context: context,
      builder: (_) => InviteUserDialog._(room: room),
    );
  }

  @override
  State<InviteUserDialog> createState() => _InviteUserDialogState();
}

class _InviteUserDialogState extends State<InviteUserDialog> {
  static final _mxidRegex = RegExp(r'^@[^:]+:.+$');
  static const _debounceDuration = Duration(milliseconds: 400);

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _error;
  bool _searching = false;
  List<Profile> _searchResults = [];
  Timer? _debounce;
  int _searchGeneration = 0;
  List<Profile>? _cachedContacts;
  Set<String>? _cachedExistingMembers;
  bool _suggestionsReady = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _existingMembers();
      _knownContacts();
      if (!mounted) return;
      setState(() => _suggestionsReady = true);
    });
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  Client? get _client {
    try {
      return widget.room.client;
    } catch (_) {
      return null;
    }
  }

  Set<String> _existingMembers() {
    if (_cachedExistingMembers != null) return _cachedExistingMembers!;
    try {
      _cachedExistingMembers = widget.room
          .getParticipants()
          .map((u) => u.id)
          .toSet();
    } catch (_) {
      _cachedExistingMembers = const <String>{};
    }
    return _cachedExistingMembers!;
  }

  List<Profile> _knownContacts() {
    if (_cachedContacts != null) return _cachedContacts!;
    final client = _client;
    if (client == null) return _cachedContacts = const [];
    try {
      _cachedContacts = knownContacts(client);
    } catch (_) {
      _cachedContacts = const [];
    }
    return _cachedContacts!;
  }

  void _onQueryChanged(String text) {
    _debounce?.cancel();
    final query = text.trim();
    setState(() => _error = null);
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(_debounceDuration, () {
      unawaited(_runSearch(query));
    });
  }

  Future<void> _runSearch(String query) async {
    final client = _client;
    if (client == null) return;
    _searchGeneration++;
    final gen = _searchGeneration;
    setState(() => _searching = true);
    try {
      final response = await client.searchUserDirectory(query, limit: 20);
      if (!mounted || gen != _searchGeneration) return;
      setState(() {
        _searchResults = response.results;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || gen != _searchGeneration) return;
      setState(() {
        _searchResults = [];
        _searching = false;
      });
    }
  }

  void _selectProfile(Profile profile) {
    Navigator.pop(context, profile.userId);
  }

  void _submit() {
    final mxid = _controller.text.trim();
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

  List<Widget> _buildSuggestions(ColorScheme cs) {
    if (!_suggestionsReady) return [];
    final query = _controller.text.trim();
    final existing = _existingMembers();
    final source = query.isEmpty ? _knownContacts() : _searchResults;
    final filtered = source.where((p) => !existing.contains(p.userId)).toList();
    if (filtered.isEmpty) return [];

    final tiles = <Widget>[];
    if (query.isEmpty) {
      tiles.add(Padding(
        padding: const EdgeInsets.only(left: 12, top: 8, bottom: 4),
        child: Text(
          'Recent contacts',
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),);
    }
    for (final p in filtered) {
      final label = p.displayName ?? p.userId;
      final initial = label.isNotEmpty ? label.characters.first.toUpperCase() : '?';
      tiles.add(ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: cs.primaryContainer,
          child: Text(
            initial,
            style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13),
          ),
        ),
        title: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
        subtitle: p.displayName != null
            ? Text(
                p.userId,
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              )
            : null,
        onTap: () => _selectProfile(p),
      ),);
    }
    return tiles;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final suggestions = _buildSuggestions(cs);

    return Dialog(
      child: SizedBox(
        width: 400,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Invite user', style: tt.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Matrix ID',
                  hintText: '@user:server.com or display name',
                  border: const OutlineInputBorder(),
                  errorText: _error,
                ),
                onChanged: _onQueryChanged,
                onSubmitted: (_) => _submit(),
              ),
              if (_searching)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: LinearProgressIndicator(),
                ),
              if (!_suggestionsReady)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                )
              else if (suggestions.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: suggestions,
                  ),
                ),
              const SizedBox(height: 16),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: _submit,
                    child: const Text('Invite'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
