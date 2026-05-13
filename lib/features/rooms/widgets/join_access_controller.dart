import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/models/join_mode.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/space_access_service.dart';
import 'package:kohera/shared/widgets/join_access_section.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

typedef CandidateSpacesBuilder = List<Room> Function(
  BuildContext context,
  Room room,
);

class JoinAccessController extends StatefulWidget {
  const JoinAccessController({
    required this.room,
    this.candidatesBuilder,
    super.key,
  });

  final Room room;

  /// Optional override for the picker's candidate list. Defaults to all
  /// joined spaces minus the room itself.
  final CandidateSpacesBuilder? candidatesBuilder;

  @override
  State<JoinAccessController> createState() => _JoinAccessControllerState();
}

class _JoinAccessControllerState extends State<JoinAccessController> {
  static const _saveDebounce = Duration(milliseconds: 500);

  late JoinMode _mode;
  late List<Room> _allowed;
  bool _busy = false;
  String? _error;
  Timer? _saveTimer;

  SpaceAccessService get _service => context.read<MatrixService>().spaceAccess;

  Client get _client => context.read<MatrixService>().client;

  @override
  void initState() {
    super.initState();
    _mode = _service.getJoinMode(widget.room);
    _allowed = _resolveAllowed();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  List<Room> _resolveAllowed() {
    final ids = _service.allowedSpaceIds(widget.room);
    return ids
        .map(_client.getRoomById)
        .whereType<Room>()
        .toList(growable: false);
  }

  List<Room> get _candidates {
    final builder = widget.candidatesBuilder;
    if (builder != null) return builder(context, widget.room);
    final selection = context.read<MatrixService>().selection;
    return selection.spaces.where((s) => s.id != widget.room.id).toList();
  }

  bool get _needsUpgrade {
    if (!_mode.isRestrictedFamily) return false;
    return _service.needsUpgradeForRestricted(
      widget.room,
      wantKnock: _mode == JoinMode.knockRestricted,
    );
  }

  void _scheduleApply() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, _applyIfValid);
  }

  Future<void> _applyIfValid() async {
    if (_needsUpgrade) return;
    if (_mode.isRestrictedFamily && _allowed.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.applyJoinMode(
        roomId: widget.room.id,
        mode: _mode,
        allowSpaceIds: _allowed.map((r) => r.id).toList(growable: false),
      );
    } catch (e) {
      debugPrint('[Kohera] applyJoinMode failed: $e');
      if (mounted) {
        setState(() => _error = MatrixService.friendlyAuthError(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onUpgradeRequested() async {
    final wantKnock = _mode == JoinMode.knockRestricted;
    final newVersion =
        await _service.pickRestrictedRoomVersion(wantKnock: wantKnock);
    if (!mounted) return;
    if (newVersion == null) {
      setState(() =>
          _error = 'Server does not advertise a compatible room version.',);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upgrade room?'),
        content: Text(
          'Upgrading this room creates a replacement room (v$newVersion). '
          'Members will need to rejoin via the tombstone. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final newRoomId = await _service.upgradeRoomTo(widget.room, newVersion);
      try {
        await _client
            .waitForRoomInSync(newRoomId, join: true)
            .timeout(const Duration(seconds: 30));
      } on TimeoutException {
        debugPrint('[Kohera] new room $newRoomId did not sync in time');
      }
      await _service.rewireParentSpaces(widget.room.id, newRoomId);
      await _service.applyJoinMode(
        roomId: newRoomId,
        mode: _mode,
        allowSpaceIds: _allowed.map((r) => r.id).toList(growable: false),
      );
      if (mounted) {
        context.goNamed(
          Routes.room,
          pathParameters: {'roomId': newRoomId},
        );
      }
    } catch (e) {
      debugPrint('[Kohera] room upgrade failed: $e');
      if (mounted) {
        setState(() => _error = MatrixService.friendlyAuthError(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canEdit =
        widget.room.canChangeStateEvent(EventTypes.RoomJoinRules) && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        JoinAccessSection(
          mode: _mode,
          allowedSpaces: _allowed,
          candidateSpaces: _candidates,
          needsUpgrade: _needsUpgrade,
          canEdit: canEdit,
          onModeChanged: (m) {
            setState(() {
              _mode = m;
              if (_mode.isRestrictedFamily && _allowed.isEmpty) {
                _allowed = List.of(_candidates);
              }
            });
            _scheduleApply();
          },
          onAllowedSpacesChanged: (list) {
            setState(() => _allowed = list);
            _scheduleApply();
          },
          onUpgradeRequested: _onUpgradeRequested,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child:
                Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
          ),
      ],
    );
  }
}
