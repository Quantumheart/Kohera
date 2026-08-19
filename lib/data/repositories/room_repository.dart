import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/data/models/kohera_push_rule_state.dart';
import 'package:kohera/data/models/kohera_room_member.dart';
import 'package:kohera/data/models/kohera_room_permissions.dart';
import 'package:kohera/data/models/kohera_room_summary.dart';
import 'package:kohera/data/models/space_node.dart';
import 'package:kohera/data/resolvers/room_member_list_resolver.dart';
import 'package:kohera/data/resolvers/room_permissions_resolver.dart';
import 'package:kohera/data/resolvers/room_summary_resolver.dart';
import 'package:matrix/matrix.dart';

class RoomRepository extends ChangeNotifier {
  RoomRepository({required MatrixService matrix}) : _matrix = matrix {
    _syncSub = _matrix.client.onSync.stream.listen((_) {
      _matrix.selection.invalidateSpaceTree();
      notifyListeners();
    });
    _matrix.addListener(_onMatrixChanged);
  }

  MatrixService _matrix;
  StreamSubscription<SyncUpdate>? _syncSub;
  bool _disposed = false;

  void updateMatrixService(MatrixService matrix) {
    if (identical(matrix, _matrix)) return;
    _matrix.removeListener(_onMatrixChanged);
    _matrix = matrix;
    unawaited(_syncSub?.cancel());
    _syncSub = _matrix.client.onSync.stream.listen((_) {
      _matrix.selection.invalidateSpaceTree();
      notifyListeners();
    });
    _matrix.addListener(_onMatrixChanged);
    notifyListeners();
  }

  void _onMatrixChanged() {
    if (!_disposed) notifyListeners();
  }

  // ── Domain model: room summaries ──────────────────────────────

  KoheraRoomSummary? summaryFor(String roomId) {
    final room = _matrix.client.getRoomById(roomId);
    if (room == null) return null;
    return _matrix.selection.summaryFor(room);
  }

  List<KoheraRoomSummary> get roomSummaries {
    final myUserId = _matrix.client.userID;
    return _matrix.client.rooms
        .where((r) => !r.isSpace && r.membership == Membership.join)
        .map((r) => const RoomSummaryResolver()(r, myUserId: myUserId))
        .toList();
  }

  List<KoheraRoomSummary> get orphanRoomSummaries {
    final myUserId = _matrix.client.userID;
    return _matrix.selection.orphanRooms
        .map((r) => const RoomSummaryResolver()(r, myUserId: myUserId))
        .toList();
  }

  List<KoheraRoomSummary> summariesForSpace(String spaceId) {
    final myUserId = _matrix.client.userID;
    return _matrix.selection
        .roomsForSpace(spaceId)
        .map((r) => const RoomSummaryResolver()(r, myUserId: myUserId))
        .toList();
  }

  // ── Domain model: room permissions ───────────────────────────

  KoheraRoomPermissions? permissionsFor(String roomId) {
    final room = _matrix.client.getRoomById(roomId);
    if (room == null) return null;
    return const RoomPermissionsResolver().convert(
      room,
      myUserId: _matrix.client.userID ?? '',
    );
  }

  // ── Domain model: room member list ────────────────────────────

  Future<KoheraRoomMemberList?> memberListFor(String roomId) async {
    final room = _matrix.client.getRoomById(roomId);
    if (room == null) return null;
    return const RoomMemberListResolver().resolve(room);
  }

  // ── Selection state ──────────────────────────────────────────

  Set<String> get selectedSpaceIds => _matrix.selection.selectedSpaceIds;
  String? get selectedRoomId => _matrix.selection.selectedRoomId;

  void selectSpace(String? spaceId) =>
      _matrix.selection.selectSpace(spaceId);
  void selectRoom(String? roomId) => _matrix.selection.selectRoom(roomId);
  void toggleSpaceSelection(String spaceId) =>
      _matrix.selection.toggleSpaceSelection(spaceId);
  void clearSpaceSelection() => _matrix.selection.clearSpaceSelection();

  // ── Space tree ───────────────────────────────────────────────

  List<SpaceNode> get spaceTree => _matrix.selection.spaceTree;

  // ── Room operations (write path) ──────────────────────────────

  Future<void> joinRoom(String roomId) => _matrix.client.joinRoom(roomId);

  Future<void> leaveRoom(String roomId) async {
    final room = _matrix.client.getRoomById(roomId);
    if (room != null) await room.leave();
  }

  Future<void> setFavourite(String roomId, bool favourite) async {
    final room = _matrix.client.getRoomById(roomId);
    if (room != null) await room.setFavourite(favourite);
  }

  Future<void> setPushRuleState(String roomId, KoheraPushRuleState state) async {
    final room = _matrix.client.getRoomById(roomId);
    if (room != null) {
      await room.setPushRuleState(_toSdkPushRuleState(state));
    }
  }

  // ── Sync stream ──────────────────────────────────────────────

  Stream<SyncUpdate> get onSync => _matrix.client.onSync.stream;

  // ── Transitional raw room access ──────────────────────────────

  @Deprecated('Use summaryFor/permissionsFor/memberListFor instead')
  Room? rawRoom(String roomId) => _matrix.client.getRoomById(roomId);

  // ── Helpers ──────────────────────────────────────────────────

  PushRuleState _toSdkPushRuleState(KoheraPushRuleState state) {
    return switch (state) {
      KoheraPushRuleState.notify => PushRuleState.notify,
      KoheraPushRuleState.mentionsOnly => PushRuleState.mentionsOnly,
      KoheraPushRuleState.dontNotify => PushRuleState.dontNotify,
    };
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _matrix.removeListener(_onMatrixChanged);
    unawaited(_syncSub?.cancel());
    _syncSub = null;
    super.dispose();
  }
}
