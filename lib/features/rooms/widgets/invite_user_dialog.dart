import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kohera/core/extensions/context_extension.dart';
import 'package:kohera/shared/models/kohera_user_summary.dart';

/// SDK-free inputs for [InviteUserDialog].
///
/// The parent (which retains `Room`/`Client` access) computes the member set,
/// contact suggestions, and the user-directory search callback, then passes
/// them in. The dialog itself has no `package:matrix/matrix.dart` dependency.
class InviteUserDialogParams {
  const InviteUserDialogParams({
    required this.roomId,
    required this.existingMemberIds,
    required this.knownContacts,
    required this.roomContacts,
    required this.onSearchUserDirectory,
    this.canonicalAlias,
  });

  /// The Matrix room/space ID the user will be invited to.
  final String roomId;

  /// Canonical alias (``#room:server``) if the room has one. Used to build a
  /// shareable matrix.to invite link.
  final String? canonicalAlias;

  /// MXIDs already participating in the room (to exclude from suggestions).
  final Set<String> existingMemberIds;

  /// Recent DM contacts, as SDK-free summaries.
  final List<KoheraUserSummary> knownContacts;

  /// Contacts from other joined group rooms, as SDK-free summaries.
  final List<KoheraUserSummary> roomContacts;

  /// Searches the homeserver user directory for [query], returning matches
  /// as SDK-free summaries.
  final Future<List<KoheraUserSummary>> Function(String query)
      onSearchUserDirectory;
}

/// A reusable dialog that prompts for a Matrix user ID to invite to a room
/// or space. Suggests recent contacts and searches the homeserver's user
/// directory as the user types.
///
/// SDK-free: all data and search access is provided via [InviteUserDialogParams].
///
/// Returns the validated MXID string on success, or `null` if cancelled.
class InviteUserDialog extends StatefulWidget {
  const InviteUserDialog({required this.params, super.key});

  final InviteUserDialogParams params;

  static Future<String?> show(
    BuildContext context, {
    required InviteUserDialogParams params,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => InviteUserDialog(params: params),
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
  List<KoheraUserSummary> _searchResults = [];
  Timer? _debounce;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
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
    _searchGeneration++;
    final gen = _searchGeneration;
    setState(() => _searching = true);
    List<KoheraUserSummary> results;
    try {
      results = await widget.params.onSearchUserDirectory(query);
    } catch (_) {
      results = const [];
    }
    if (!mounted || gen != _searchGeneration) return;
    setState(() {
      _searchResults = results;
      _searching = false;
    });
  }

  void _selectProfile(KoheraUserSummary profile) {
    Navigator.pop(context, profile.userId);
  }

  void _copyInviteLink() {
    final alias = widget.params.canonicalAlias;
    final link = 'https://matrix.to/#/${alias ?? widget.params.roomId}';
    unawaited(Clipboard.setData(ClipboardData(text: link)));
    context.showSnack('Invite link copied to clipboard');
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
    final query = _controller.text.trim();
    final existing = widget.params.existingMemberIds;
    final tiles = <Widget>[];

    if (query.isNotEmpty) {
      final filtered = _searchResults
          .where((p) => !existing.contains(p.userId))
          .map((p) => _profileTile(p, cs))
          .toList();
      return filtered;
    }

    final dmContacts = widget.params.knownContacts
        .where((p) => !existing.contains(p.userId))
        .toList();
    final groupContacts = widget.params.roomContacts
        .where((p) => !existing.contains(p.userId))
        .toList();

    if (dmContacts.isEmpty && groupContacts.isEmpty) return [];

    if (dmContacts.isNotEmpty) {
      tiles.add(_sectionLabel('Recent contacts', cs));
      tiles.addAll(dmContacts.map((p) => _profileTile(p, cs)));
    }

    if (groupContacts.isNotEmpty) {
      tiles.add(_sectionLabel('From other rooms', cs));
      tiles.addAll(groupContacts.map((p) => _profileTile(p, cs)));
    }

    return tiles;
  }

  Widget _sectionLabel(String text, ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(left: 12, top: 8, bottom: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      );

  Widget _profileTile(KoheraUserSummary p, ColorScheme cs) {
    final label = p.displayname;
    final initial =
        label.isNotEmpty ? label.characters.first.toUpperCase() : '?';
    return ListTile(
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
      subtitle: p.displayname != p.userId
          ? Text(
              p.userId,
              style: const TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            )
          : null,
      onTap: () => _selectProfile(p),
    );
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
              if (suggestions.isNotEmpty)
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
                    onPressed: _copyInviteLink,
                    child: const Text('Copy invite link'),
                  ),
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
