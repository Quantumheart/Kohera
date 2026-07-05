import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/models/join_mode.dart';
import 'package:kohera/core/routing/route_names.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/space_access_service.dart';
import 'package:kohera/core/utils/confirm_dialog.dart';
import 'package:kohera/shared/widgets/join_access_section.dart';
import 'package:provider/provider.dart';

typedef CandidateSpacesBuilder = List<SpaceRef> Function(
  BuildContext context,
  String roomId,
);

class JoinAccessController extends StatefulWidget {
  const JoinAccessController({
    required this.roomId,
    this.candidatesBuilder,
    super.key,
  });

  final String roomId;

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
  late List<SpaceRef> _allowed;
  bool _busy = false;
  bool _savedHint = false;
  String? _error;
  Timer? _saveTimer;
  Timer? _savedHintTimer;
  StreamSubscription<dynamic>? _syncSub;
  bool _userDirty = false;

  SpaceAccessService get _service => context.read<MatrixService>().spaceAccess;

  @override
  void initState() {
    super.initState();
    final room = context.read<MatrixService>().client.getRoomById(widget.roomId);
    if (room != null) {
      _mode = _service.getJoinMode(room);
    } else {
      _mode = JoinMode.invite;
    }
    _allowed = _resolveAllowed();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSub ??= context.read<MatrixService>().client.onSync.stream.listen(_onSync);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _savedHintTimer?.cancel();
    unawaited(_syncSub?.cancel());
    super.dispose();
  }

  void _onSync(dynamic _) {
    if (_userDirty || _busy || (_saveTimer?.isActive ?? false)) return;
    final room = context.read<MatrixService>().client.getRoomById(widget.roomId);
    if (room == null) return;
    final remoteMode = _service.getJoinMode(room);
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

  bool _sameIds(List<SpaceRef> a, List<SpaceRef> b) {
    final ai = a.map((r) => r.id).toSet();
    final bi = b.map((r) => r.id).toSet();
    return ai.length == bi.length && ai.containsAll(bi);
  }

  List<SpaceRef> _resolveAllowed() {
    final room = context.read<MatrixService>().client.getRoomById(widget.roomId);
    if (room == null) return const [];
    final ids = _service.allowedSpaceIds(room);
    final client = context.read<MatrixService>().client;
    return ids
        .map(client.getRoomById)
        .where((r) => r != null)
        .map((r) => (id: r!.id, displayname: r.getLocalizedDisplayname()))
        .toList(growable: false);
  }

  List<SpaceRef> get _candidates {
    final builder = widget.candidatesBuilder;
    if (builder != null) return builder(context, widget.roomId);
    final selection = context.read<MatrixService>().selection;
    return selection.spaces
        .where((s) => s.id != widget.roomId)
        .map((s) => (id: s.id, displayname: s.getLocalizedDisplayname()))
        .toList();
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
    final room = context.read<MatrixService>().client.getRoomById(widget.roomId);
    if (room == null) return false;
    return _service.needsUpgradeForRestricted(
      room,
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
        roomId: widget.roomId,
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
      setState(() => _error = 'Server does not advertise a compatible room version.');
      return;
    }

    final confirmed = await confirmDialog(
      context,
      title: 'Upgrade room?',
      message: 'Upgrading this room creates a replacement room (v$newVersion). '
          'Members will need to rejoin via the tombstone. Continue?',
      confirmLabel: 'Upgrade',
    );
    if (!confirmed || !mounted) return;

    final matrix = context.read<MatrixService>();
    final room = matrix.client.getRoomById(widget.roomId);
    if (room == null) return;
    final parents = matrix.selection.parentSpacesOf(room);

    setState(() {
      _busy = true;
      _savedHint = false;
      _error = null;
    });
    try {
      final newRoomId = await _service.upgradeRoomTo(room, newVersion);
      try {
        await matrix.client
            .waitForRoomInSync(newRoomId, join: true)
            .timeout(const Duration(seconds: 30));
      } on TimeoutException {
        debugPrint('[Kohera] new room $newRoomId did not sync in time');
      }
      await _service.rewireParentSpaces(
        oldRoomId: widget.roomId,
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
          pathParameters: {RouteParams.roomId: newRoomId},
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
    final room = context.read<MatrixService>().client.getRoomById(widget.roomId);
    final canEdit =
        room?.canChangeStateEvent('m.room.join_rules') == true && !_busy;
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
            setState(() => _allowed = _idsToRefs(list));
            _scheduleApply();
          },
          onUpgradeRequested: _onUpgradeRequested,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
          ),
      ],
    );
  }

  /// Converts a list of room IDs back to [SpaceRef] by looking up each room.
  List<SpaceRef> _idsToRefs(List<String> ids) {
    final client = context.read<MatrixService>().client;
    return ids
        .map(client.getRoomById)
        .where((r) => r != null)
        .map((r) => (id: r!.id, displayname: r.getLocalizedDisplayname()))
        .toList(growable: false);
  }
}
