import 'dart:async';

import 'package:flutter/material.dart' hide Visibility;
import 'package:kohera/core/models/join_mode.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/utils/known_contacts.dart';
import 'package:kohera/shared/widgets/join_access_section.dart';
import 'package:matrix/matrix.dart';

// ── New Room dialog ───────────────────────────────────────────

class NewRoomDialog extends StatefulWidget {
  const NewRoomDialog._({
    required this.matrixService,
    this.parentSpaceIds,
  });

  final MatrixService matrixService;
  final Set<String>? parentSpaceIds;

  static Future<void> show(
    BuildContext context, {
    required MatrixService matrixService,
    Set<String>? parentSpaceIds,
  }) {
    return showDialog(
      context: context,
      builder: (_) => NewRoomDialog._(
        matrixService: matrixService,
        parentSpaceIds: parentSpaceIds,
      ),
    );
  }

  @override
  State<NewRoomDialog> createState() => _NewRoomDialogState();
}

class _NewRoomDialogState extends State<NewRoomDialog> {
  final _nameController = TextEditingController();
  final _topicController = TextEditingController();
  final _inviteController = TextEditingController();
  final _inviteFocusNode = FocusNode();
  bool _isPublic = false;
  bool _enableEncryption = true;
  bool _loading = false;
  bool _inviteSearching = false;
  String? _nameError;
  String? _networkError;
  final List<String> _invitedUsers = [];
  List<Profile> _inviteSearchResults = [];
  Timer? _debounce;
  int _searchGeneration = 0;
  List<Profile>? _cachedContacts;
  bool _addToSpace = true;
  final Set<String> _targetSpaceIds = {};

  // Restricted-join state (only relevant when created inside a parent space).
  JoinMode _joinMode = JoinMode.invite;
  List<Room> _allowedJoinSpaces = const [];
  Map<JoinMode, String> _disabledModes = const {};
  String? _restrictedRoomVersion;
  bool _restrictedAvailable = false;

  @override
  void initState() {
    super.initState();
    _inviteFocusNode.addListener(_onFocusChanged);
    _initTargetSpaces();
    unawaited(_loadRestrictedCapabilities());
  }

  Future<void> _loadRestrictedCapabilities() async {
    if (_eligibleParentSpaces().isEmpty) return;
    final access = widget.matrixService.spaceAccess;
    final knockVersion =
        await access.pickRestrictedRoomVersion(wantKnock: true);
    final basicVersion =
        await access.pickRestrictedRoomVersion(wantKnock: false);
    if (!mounted) return;
    setState(() {
      _restrictedRoomVersion = knockVersion ?? basicVersion;
      _restrictedAvailable = _restrictedRoomVersion != null;
      _disabledModes = knockVersion == null
          ? const {
              JoinMode.knockRestricted: 'Not supported by this server',
            }
          : const <JoinMode, String>{};
      if (_restrictedAvailable && _allowedJoinSpaces.isEmpty) {
        final parents = _eligibleParentSpaces();
        if (parents.isNotEmpty) {
          _joinMode = JoinMode.restricted;
          _allowedJoinSpaces = List.of(parents);
        }
      }
    });
    if (!_restrictedAvailable) {
      final versions = await access.serverSupportedRoomVersions();
      debugPrint(
        '[Kohera] Restricted join unavailable: server room versions=$versions',
      );
    }
  }

  void _initTargetSpaces() {
    final eligible = _eligibleParentSpaces();
    if (eligible.isEmpty) {
      _addToSpace = false;
    } else {
      _targetSpaceIds.addAll(eligible.map((s) => s.id));
    }
  }

  List<Room> _eligibleParentSpaces() {
    final source = widget.parentSpaceIds ??
        widget.matrixService.selection.selectedSpaceIds;
    final eligible = <Room>[];
    for (final id in source) {
      final space = widget.matrixService.client.getRoomById(id);
      if (space != null && space.canChangeStateEvent('m.space.child')) {
        eligible.add(space);
      }
    }
    return eligible;
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _inviteFocusNode.removeListener(_onFocusChanged);
    _nameController.dispose();
    _topicController.dispose();
    _inviteController.dispose();
    _inviteFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  static final _mxidRegex = RegExp(r'^@[^:]+:.+$');

  // ── Known contacts ──────────────────────────────────────────

  List<Profile> _knownContacts() {
    return _cachedContacts ??= knownContacts(widget.matrixService.client);
  }

  // ── Invite search ───────────────────────────────────────────

  void _onInviteSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _inviteSearchResults = [];
        _inviteSearching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(_searchInviteDirectory(query.trim()));
    });
  }

  Future<void> _searchInviteDirectory(String query) async {
    _searchGeneration++;
    final gen = _searchGeneration;
    setState(() {
      _inviteSearching = true;
      _networkError = null;
    });

    try {
      final response = await widget.matrixService.client
          .searchUserDirectory(query, limit: 20);
      if (!mounted || gen != _searchGeneration) return;
      setState(() {
        _inviteSearchResults = response.results;
        _inviteSearching = false;
      });
    } catch (e) {
      if (!mounted || gen != _searchGeneration) return;
      setState(() {
        _inviteSearching = false;
        _networkError = MatrixService.friendlyAuthError(e);
      });
    }
  }

  void _addInviteFromProfile(Profile profile) {
    final mxid = profile.userId;
    _inviteController.clear();
    setState(() {
      if (!_invitedUsers.contains(mxid)) {
        _invitedUsers.add(mxid);
        _networkError = null;
      }
      _inviteSearchResults = [];
    });
  }

  void _addInvite() {
    final mxid = _inviteController.text.trim();
    if (mxid.isEmpty) return;
    if (!_mxidRegex.hasMatch(mxid)) {
      setState(() => _networkError = 'Invalid Matrix ID (use @user:server)');
      return;
    }
    if (_invitedUsers.contains(mxid)) {
      _inviteController.clear();
      return;
    }
    _inviteController.clear();
    setState(() {
      _invitedUsers.add(mxid);
      _networkError = null;
      _inviteSearchResults = [];
    });
  }

  void _removeInvite(String userId) {
    setState(() => _invitedUsers.remove(userId));
  }

  // ── Invite suggestions list ─────────────────────────────────

  List<Widget> _inviteSuggestions(ColorScheme cs) {
    final query = _inviteController.text.trim();
    final profiles = query.isEmpty ? _knownContacts() : _inviteSearchResults;
    final filtered =
        profiles.where((p) => !_invitedUsers.contains(p.userId)).toList();
    if (filtered.isEmpty) return [];

    final tiles = <Widget>[];
    if (query.isEmpty && filtered.isNotEmpty) {
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
      tiles.add(ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: cs.primaryContainer,
          child: Text(
            ((p.displayName ?? p.userId).isNotEmpty ? (p.displayName ?? p.userId).characters.first.toUpperCase() : '?'),
            style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13),
          ),
        ),
        title: Text(p.displayName ?? p.userId,
            overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14),),
        subtitle: p.displayName != null
            ? Text(p.userId,
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis,)
            : null,
        onTap: () => _addInviteFromProfile(p),
      ),);
    }
    return tiles;
  }

  List<Widget> _buildSpaceSelection() {
    final eligible = _eligibleParentSpaces();
    if (eligible.length < 2) return [];

    return [
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Add to spaces',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      for (final space in eligible)
        CheckboxListTile(
          value: _targetSpaceIds.contains(space.id),
          onChanged: _loading
              ? null
              : (v) => setState(() {
                    if (v == true) {
                      _targetSpaceIds.add(space.id);
                    } else {
                      _targetSpaceIds.remove(space.id);
                    }
                    _addToSpace = _targetSpaceIds.isNotEmpty;
                  }),
          title: Text(space.getLocalizedDisplayname()),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
        ),
    ];
  }

  Future<void> _submit() async {
    _debounce?.cancel();
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _nameError = 'Name is required';
        _networkError = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _nameError = null;
      _networkError = null;
    });

    try {
      final client = widget.matrixService.client;
      final topic = _topicController.text.trim();

      final useRestricted = !_isPublic &&
          _restrictedAvailable &&
          _joinMode.isRestrictedFamily &&
          _allowedJoinSpaces.isNotEmpty;
      final joinRulesEvent = useRestricted
          ? widget.matrixService.spaceAccess.buildJoinRulesStateEvent(
              _joinMode,
              _allowedJoinSpaces.map((s) => s.id).toList(growable: false),
            )
          : null;

      final roomId = await client.createRoom(
        name: name,
        topic: topic.isNotEmpty ? topic : null,
        visibility: _isPublic ? Visibility.public : Visibility.private,
        roomVersion: useRestricted ? _restrictedRoomVersion : null,
        initialState: [
          if (_enableEncryption)
            StateEvent(
              content: {
                'algorithm':
                    Client.supportedGroupEncryptionAlgorithms.first,
              },
              type: EventTypes.Encryption,
            ),
          if (joinRulesEvent != null) joinRulesEvent,
        ],
        invite: _invitedUsers.isNotEmpty ? _invitedUsers : null,
      );

      await client
          .waitForRoomInSync(roomId, join: true)
          .timeout(const Duration(seconds: 30));

      // Auto-parent to selected spaces.
      if (_addToSpace && _targetSpaceIds.isNotEmpty) {
        var spaceFailures = 0;
        for (final spaceId in _targetSpaceIds) {
          final space = client.getRoomById(spaceId);
          if (space == null) continue;
          try {
            await space.setSpaceChild(roomId);
          } catch (e) {
            debugPrint('[Kohera] Failed to add room to space: $e');
            spaceFailures++;
          }
        }
        widget.matrixService.selection.invalidateSpaceTree();
        if (spaceFailures > 0 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Room created, but failed to add to $spaceFailures space(s)',
              ),
            ),
          );
        }
      }

      if (!mounted) return;
      widget.matrixService.selection.selectRoom(roomId);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _networkError = MatrixService.friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final eligible = _eligibleParentSpaces();
    final titleSuffix = eligible.length == 1
        ? ' in ${eligible.first.getLocalizedDisplayname()}'
        : '';

    return AlertDialog(
      title: Text('New Room$titleSuffix'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              enabled: !_loading,
              decoration: InputDecoration(
                labelText: 'Name',
                border: const OutlineInputBorder(),
                errorText: _nameError,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _topicController,
              enabled: !_loading,
              decoration: const InputDecoration(
                labelText: 'Topic (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _inviteController,
              focusNode: _inviteFocusNode,
              enabled: !_loading,
              decoration: InputDecoration(
                labelText: 'Invite users (optional)',
                hintText: '@user:server.com or display name',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add_rounded),
                  onPressed: _loading ? null : _addInvite,
                ),
              ),
              onChanged: _onInviteSearchChanged,
              onSubmitted: (_) => _addInvite(),
            ),
            if (_inviteSearching)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(),
              ),
            if (_inviteFocusNode.hasFocus) ...[
              Builder(builder: (_) {
                final suggestions = _inviteSuggestions(cs);
                if (suggestions.isEmpty) return const SizedBox.shrink();
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: suggestions,
                  ),
                );
              },),
            ],
            if (_invitedUsers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _invitedUsers
                        .map((u) => Chip(
                              label: Text(u, style: const TextStyle(fontSize: 12)),
                              onDeleted: _loading ? null : () => _removeInvite(u),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),)
                        .toList(),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Public room'),
              value: _isPublic,
              onChanged: _loading
                  ? null
                  : (v) => setState(() {
                        _isPublic = v;
                        _enableEncryption = !v;
                      }),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('Enable encryption'),
              subtitle: Text(
                _isPublic
                    ? 'Not available for public rooms'
                    : 'Cannot be disabled later',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
              value: _enableEncryption,
              onChanged: _loading || _isPublic
                  ? null
                  : (v) => setState(() => _enableEncryption = v),
              contentPadding: EdgeInsets.zero,
            ),
            ..._buildSpaceSelection(),
            if (_restrictedAvailable && _eligibleParentSpaces().isNotEmpty) ...[
              const SizedBox(height: 8),
              JoinAccessSection(
                mode: _joinMode,
                allowedSpaces: _allowedJoinSpaces,
                candidateSpaces: _eligibleParentSpaces(),
                needsUpgrade: false,
                canEdit: !_loading,
                disabledModes: _disabledModes,
                padding: const EdgeInsets.symmetric(vertical: 12),
                onModeChanged: (m) => setState(() => _joinMode = m),
                onAllowedSpacesChanged: (l) =>
                    setState(() => _allowedJoinSpaces = l),
              ),
            ],
            if (_networkError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _networkError!,
                  style: TextStyle(color: cs.error, fontSize: 13),
                ),
              ),
          ],
        ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
