import 'dart:async';

import 'package:flutter/material.dart' hide Visibility;
import 'package:kohera/core/models/join_mode.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/shared/widgets/join_access_section.dart';
import 'package:kohera/shared/widgets/loading_button_child.dart';

/// SDK-free request describing the subspace the user wants to create. The
/// dialog collects these fields and hands them to [CreateSubspaceDialog.onCreateSubspace],
/// whose implementation (parent-side) performs the SDK calls.
class CreateSubspaceRequest {
  const CreateSubspaceRequest({
    required this.name,
    required this.topic,
    required this.joinMode,
    required this.allowedSpaceIds,
    required this.restrictedRoomVersion,
  });

  final String name;
  final String? topic;
  final JoinMode joinMode;
  final List<String> allowedSpaceIds;
  final String? restrictedRoomVersion;
}

/// Server capability info for restricted/knock join rules, computed
/// parent-side (via `SpaceAccessService`) and passed to the dialog.
class SubspaceCapabilities {
  const SubspaceCapabilities({
    required this.restrictedRoomVersion,
    required this.disabledModes,
  });

  /// The room version to use for restricted join rules, or `null` if the
  /// server does not support them.
  final String? restrictedRoomVersion;

  /// Join modes to disable in the picker, mapped to a tooltip reason.
  final Map<JoinMode, String> disabledModes;
}

/// Dialog to create a new subspace within a parent space.
///
/// SDK-free: display data comes from [parentSpaceRef], server capability
/// info is loaded via [loadCapabilities], and the actual room creation is
/// delegated to [onCreateSubspace]. The parent retains `Room`/`Client` access
/// and performs the SDK calls.
class CreateSubspaceDialog extends StatefulWidget {
  const CreateSubspaceDialog._({
    required this.parentSpaceRef,
    required this.loadCapabilities,
    required this.onCreateSubspace,
  });

  /// Reference (id + displayname) to the parent space.
  final SpaceRef parentSpaceRef;

  /// Loads restricted-join server capabilities.
  final Future<SubspaceCapabilities> Function() loadCapabilities;

  /// Creates the subspace described by the request. Throws on failure
  /// (the dialog catches and displays errors).
  final Future<void> Function(CreateSubspaceRequest request) onCreateSubspace;

  static Future<void> show(
    BuildContext context, {
    required SpaceRef parentSpaceRef,
    required Future<SubspaceCapabilities> Function() loadCapabilities,
    required Future<void> Function(CreateSubspaceRequest request)
        onCreateSubspace,
  }) {
    return showDialog(
      context: context,
      builder: (_) => CreateSubspaceDialog._(
        parentSpaceRef: parentSpaceRef,
        loadCapabilities: loadCapabilities,
        onCreateSubspace: onCreateSubspace,
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
  List<SpaceRef> _allowedJoinSpaces = const [];
  Map<JoinMode, String> _disabledModes = const {};
  String? _restrictedRoomVersion;
  bool _restrictedAvailable = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRestrictedCapabilities());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _loadRestrictedCapabilities() async {
    final caps = await widget.loadCapabilities();
    if (!mounted) return;
    setState(() {
      _restrictedRoomVersion = caps.restrictedRoomVersion;
      _restrictedAvailable = caps.restrictedRoomVersion != null;
      _disabledModes = caps.disabledModes;
      if (_restrictedAvailable && _allowedJoinSpaces.isEmpty) {
        _joinMode = JoinMode.restricted;
        _allowedJoinSpaces = [widget.parentSpaceRef];
      }
    });
  }

  List<SpaceRef> _refsForIds(List<String> ids) {
    final candidateById = {widget.parentSpaceRef.id: widget.parentSpaceRef};
    return ids
        .map((id) => candidateById[id] ?? (id: id, displayname: id))
        .toList();
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
      final topic = _topicController.text.trim();
      await widget.onCreateSubspace(
        CreateSubspaceRequest(
          name: name,
          topic: topic.isNotEmpty ? topic : null,
          joinMode: _joinMode,
          allowedSpaceIds:
              _allowedJoinSpaces.map((s) => s.id).toList(growable: false),
          restrictedRoomVersion: _restrictedRoomVersion,
        ),
      );
      if (!mounted) return;
      Navigator.pop(context);
    } on TimeoutException {
      debugPrint('[Kohera] Subspace creation timed out');
      if (!mounted) return;
      setState(
        () => _networkError =
            'Timed out waiting for the server. The subspace may still be created.',
      );
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
              '"${widget.parentSpaceRef.displayname}".',
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
              JoinAccessSection.refs(
                mode: _joinMode,
                allowedSpaces: _allowedJoinSpaces,
                candidateSpaces: [widget.parentSpaceRef],
                needsUpgrade: false,
                canEdit: !_loading,
                disabledModes: _disabledModes,
                padding: const EdgeInsets.symmetric(vertical: 12),
                onModeChanged: (m) => setState(() => _joinMode = m),
                onAllowedSpacesChanged: (ids) =>
                    setState(() => _allowedJoinSpaces = _refsForIds(ids)),
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
          child: LoadingButtonChild(
            loading: _loading,
            child: const Text('Create'),
          ),
        ),
      ],
    );
  }
}
