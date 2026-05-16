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
  static const _savedHintDuration = Duration(seconds: 2);

  late JoinMode _mode;
  late List<Room> _allowed;
  bool _busy = false;
  bool _savedHint = false;
  String? _error;
  Timer? _saveTimer;
  Timer? _savedHintTimer;
  StreamSubscription<SyncUpdate>? _syncSub;
  bool _userDirty = false;

  SpaceAccessService get _service => context.read<MatrixService>().spaceAccess;

  Client get _client => context.read<MatrixService>().client;

  @override
  void initState() {
    super.initState();
    _mode = _service.getJoinMode(widget.room);
    _allowed = _resolveAllowed();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSub ??= _client.onSync.stream.listen(_onSync);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _savedHintTimer?.cancel();
    unawaited(_syncSub?.cancel());
    super.dispose();
  }

  void _onSync(SyncUpdate _) {
    // Skip if the user has unsaved local edits or a write is in flight; we
    // don't want to clobber what they're typing. Refresh once that settles.
    if (_userDirty || _busy || (_saveTimer?.isActive ?? false)) return;
    final remoteMode = _service.getJoinMode(widget.room);
    final remoteAllowed = _resolveAllowed();
    final changed = remoteMode != _mode ||
        remoteAllowed.length != _allowed.length ||
        !_sameIds(remoteAllowed, _allowed);
    if (changed && mounted) {
      setState(() {
        _mode = remoteMode;
        _allowed = remoteAllowed;
      });
    }
  }

  bool _sameIds(List<Room> a, List<Room> b) {
    final ai = a.map((r) => r.id).toSet();
    final bi = b.map((r) => r.id).toSet();
    return ai.length == bi.length && ai.containsAll(bi);
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

  Map<JoinMode, String> get _disabledModes {
    if (_candidates.isEmpty) {
      const tip = 'Add this space to a parent space first';
      return const {
        JoinMode.restricted: tip,
        JoinMode.knockRestricted: tip,
      };
    }
    return const {};
  }

  bool get _needsUpgrade {
    if (!_mode.isRestrictedFamily) return false;
    return _service.needsUpgradeForRestricted(
      widget.room,
      wantKnock: _mode == JoinMode.knockRestricted,
    );
  }

  void _scheduleApply() {
    _userDirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, _applyIfValid);
  }

  Future<void> _applyIfValid() async {
    if (_needsUpgrade) return;
    if (_mode.isRestrictedFamily && _allowed.isEmpty) return;
    setState(() {
      _busy = true;
      _savedHint = false;
      _error = null;
    });
    try {
      await _service.applyJoinMode(
        roomId: widget.room.id,
        mode: _mode,
        allowSpaceIds: _allowed.map((r) => r.id).toList(growable: false),
      );
      if (mounted) {
        setState(() {
          _savedHint = true;
          _userDirty = false;
        });
        _savedHintTimer?.cancel();
        _savedHintTimer = Timer(_savedHintDuration, () {
          if (mounted) setState(() => _savedHint = false);
        });
      }
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

    final selection = context.read<MatrixService>().selection;
    final parents = selection.parentSpacesOf(widget.room);

    setState(() {
      _busy = true;
      _savedHint = false;
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
      await _service.rewireParentSpaces(
        oldRoomId: widget.room.id,
        newRoomId: newRoomId,
        parents: parents,
      );
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
          disabledModes: _disabledModes,
          saving: _busy,
          savedHint: _savedHint,
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
