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

class JoinAccessController extends StatefulWidget {
  const JoinAccessController({required this.room, super.key});

  final Room room;

  @override
  State<JoinAccessController> createState() => _JoinAccessControllerState();
}

class _JoinAccessControllerState extends State<JoinAccessController> {
  late JoinMode _mode;
  late List<Room> _allowed;
  bool _busy = false;
  String? _error;

  SpaceAccessService get _service => context.read<MatrixService>().spaceAccess;

  Client get _client => context.read<MatrixService>().client;

  @override
  void initState() {
    super.initState();
    _mode = _service.getJoinMode(widget.room);
    _allowed = _resolveAllowed();
  }

  List<Room> _resolveAllowed() {
    final ids = _service.allowedSpaceIds(widget.room);
    return ids
        .map(_client.getRoomById)
        .whereType<Room>()
        .toList(growable: false);
  }

  List<Room> get _candidates {
    final selection = context.read<MatrixService>().selection;
    return selection.spaces.where((s) => s.id != widget.room.id).toList();
  }

  bool _isRestrictedFamily(JoinMode m) =>
      m == JoinMode.restricted || m == JoinMode.knockRestricted;

  bool get _needsUpgrade {
    if (!_isRestrictedFamily(_mode)) return false;
    return _service.needsUpgradeForRestricted(
      widget.room,
      wantKnock: _mode == JoinMode.knockRestricted,
    );
  }

  Future<void> _applyIfValid() async {
    if (_needsUpgrade) return;
    if (_isRestrictedFamily(_mode) && _allowed.isEmpty) return;
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upgrade room?'),
        content: const Text(
          'Upgrading this room creates a replacement room (v10). '
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
      final newRoomId = await _service.upgradeRoomTo(widget.room, '10');
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
            setState(() => _mode = m);
            unawaited(_applyIfValid());
          },
          onAllowedSpacesChanged: (list) {
            setState(() => _allowed = list);
            unawaited(_applyIfValid());
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
