import 'dart:async';

import 'package:flutter/material.dart' hide Visibility;
import 'package:kohera/core/models/join_mode.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/shared/widgets/join_access_section.dart';
import 'package:matrix/matrix.dart';

/// Dialog to create a new subspace within a parent space.
///
/// Creates a new space room and registers it as a child of [parentSpace]
/// via `setSpaceChild`.
class CreateSubspaceDialog extends StatefulWidget {
  const CreateSubspaceDialog._({
    required this.matrixService,
    required this.parentSpace,
  });

  final MatrixService matrixService;
  final Room parentSpace;

  static Future<void> show(
    BuildContext context, {
    required MatrixService matrixService,
    required Room parentSpace,
  }) {
    return showDialog(
      context: context,
      builder: (_) => CreateSubspaceDialog._(
        matrixService: matrixService,
        parentSpace: parentSpace,
      ),
    );
  }

  @override
  State<CreateSubspaceDialog> createState() => _CreateSubspaceDialogState();
}

class _CreateSubspaceDialogState extends State<CreateSubspaceDialog> {
  final _nameController = TextEditingController();
  final _topicController = TextEditingController();
  bool _loading = false;
  String? _nameError;
  String? _networkError;

  JoinMode _joinMode = JoinMode.invite;
  List<Room> _allowedJoinSpaces = const [];
  Set<JoinMode> _disabledModes = const {};
  String? _restrictedRoomVersion;
  bool _restrictedAvailable = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRestrictedCapabilities());
  }

  Future<void> _loadRestrictedCapabilities() async {
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
          ? const {JoinMode.knockRestricted}
          : const <JoinMode>{};
      if (_restrictedAvailable && _allowedJoinSpaces.isEmpty) {
        _joinMode = JoinMode.restricted;
        _allowedJoinSpaces = [widget.parentSpace];
      }
      if (!_restrictedAvailable) {
        debugPrint(
          '[Kohera] Restricted join unavailable: '
          'server room versions has no v8+',
        );
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
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

      final useRestricted = _restrictedAvailable &&
          _joinMode.isRestrictedFamily &&
          _allowedJoinSpaces.isNotEmpty;
      final joinRulesEvent = useRestricted
          ? widget.matrixService.spaceAccess.buildJoinRulesStateEvent(
              _joinMode,
              _allowedJoinSpaces.map((s) => s.id).toList(growable: false),
            )
          : null;

      // Create the subspace room.
      final roomId = await client.createRoom(
        name: name,
        topic: topic.isNotEmpty ? topic : null,
        creationContent: {'type': 'm.space'},
        visibility: Visibility.private,
        roomVersion: useRestricted ? _restrictedRoomVersion : null,
        initialState: [
          if (joinRulesEvent != null) joinRulesEvent,
        ],
        powerLevelContentOverride: {'events_default': 100},
      );

      await client
          .waitForRoomInSync(roomId, join: true)
          .timeout(const Duration(seconds: 30));

      // Register as child of the parent space.
      await widget.parentSpace.setSpaceChild(roomId);
      widget.matrixService.selection.invalidateSpaceTree();

      debugPrint('[Kohera] Subspace created: $roomId under ${widget.parentSpace.id}');

      if (!mounted) return;
      Navigator.pop(context);
    } on TimeoutException {
      debugPrint('[Kohera] Subspace creation timed out');
      if (!mounted) return;
      setState(() => _networkError =
          'Timed out waiting for the server. The subspace may still be created.',);
    } catch (e) {
      debugPrint('[Kohera] Subspace creation failed: $e');
      if (!mounted) return;
      setState(() => _networkError = MatrixService.friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Create subspace'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This subspace will be created inside '
              '"${widget.parentSpace.getLocalizedDisplayname()}".',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 16),
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
            if (_restrictedAvailable) ...[
              const SizedBox(height: 8),
              JoinAccessSection(
                mode: _joinMode,
                allowedSpaces: _allowedJoinSpaces,
                candidateSpaces: [widget.parentSpace],
                needsUpgrade: false,
                canEdit: !_loading,
                disabledModes: _disabledModes,
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
