import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/utils/known_contacts.dart';
import 'package:matrix/matrix.dart' hide Visibility;

/// A reusable dialog that prompts for a Matrix user ID to invite to a room.
///
/// Returns the validated MXID string on success, or `null` if cancelled.
class InviteUserDialog extends StatefulWidget {
  const InviteUserDialog._({required this.room});

  final Room room;

  /// Shows the invite dialog and returns the entered MXID, or `null`.
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
  static const _dialogWidth = 400.0;
  static final _mxidRegex = RegExp(r'^@[^:]+:.+$');
  final _controller = TextEditingController();
  String _query = '';
  String? _error;
  bool _searching = false;
  List<Profile> _searchResults = [];
  Timer? _debounce;
  int _searchGeneration = 0;
  List<Profile>? _cachedContacts;
  Set<String>? _cachedMemberIds;

  @override
  void dispose() {
    _controller.dispose();
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

  void _onTextChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    _searchGeneration++;
    setState(() {
      _query = query;
      _error = null;
      if (query.isEmpty) {
        _searchResults = [];
        _searching = false;
      }
    });
    if (query.isEmpty) return;
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
    final mxid = (override ?? _controller.text).trim();
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

  // ── Suggestion list ─────────────────────────────────────────

  List<Profile> _suggestions() {
    if (_query.isEmpty) return _knownContacts();
    final members = _memberIds();
    return _searchResults.where((p) => !members.contains(p.userId)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final suggestions = _suggestions();
    final showHeader = _query.isEmpty && suggestions.isNotEmpty;

    return SimpleDialog(
      title: const Text('Invite user'),
      contentPadding: const EdgeInsets.only(top: 12, bottom: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
          child: SizedBox(
            width: _dialogWidth,
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Matrix ID or display name',
                hintText: '@user:server.com',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search_rounded),
                errorText: _error,
              ),
              onChanged: _onTextChanged,
              onSubmitted: (_) => _submit(),
            ),
          ),
        ),
        SizedBox(
          width: _dialogWidth,
          height: 4,
          child: _searching ? const LinearProgressIndicator() : null,
        ),
        if (showHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
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
          ),
        if (suggestions.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: SizedBox(
              width: _dialogWidth,
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: suggestions.length,
                itemBuilder: (context, i) {
                  final p = suggestions[i];
                  return _SuggestionOption(
                    profile: p,
                    onTap: () => _submit(p.userId),
                  );
                },
              ),
            ),
          )
        else if (_query.isNotEmpty && !_searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: Text(
              'No matching users. Press Enter to invite by Matrix ID.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

// ── Suggestion option ─────────────────────────────────────────

class _SuggestionOption extends StatelessWidget {
  const _SuggestionOption({required this.profile, required this.onTap});

  final Profile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = profile.displayName;
    final firstChar = (name ?? profile.userId).isNotEmpty
        ? (name ?? profile.userId).characters.first.toUpperCase()
        : '?';
    return SimpleDialogOption(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      onPressed: onTap,
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: cs.primaryContainer,
            child: Text(
              firstChar,
              style: TextStyle(color: cs.onPrimaryContainer, fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name ?? profile.userId,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
                if (name != null)
                  Text(
                    profile.userId,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
