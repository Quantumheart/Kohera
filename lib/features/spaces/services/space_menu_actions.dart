import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/features/spaces/models/kohera_push_rule_state.dart';
import 'package:kohera/features/spaces/widgets/create_subspace_dialog.dart'
    show CreateSubspaceRequest;
import 'package:kohera/shared/models/kohera_room_summary.dart';
import 'package:matrix/matrix.dart';


/// Service layer that encapsulates all SDK operations needed by the space
/// context menu and space rail widgets.
///
/// Widgets call these methods with `String spaceId` and receive Kohera-owned
/// types. The SDK `Room` is looked up internally and never exposed.
class SpaceMenuActions {
  SpaceMenuActions(this._matrix);

  final MatrixService _matrix;

  /// Whether the user can invite people to the space.
  bool canInvite(String spaceId) {
    final space = _matrix.client.getRoomById(spaceId);
    return space?.canInvite ?? false;
  }

  /// Whether the user can manage space children (add/remove rooms).
  bool canManageChildren(String spaceId) {
    final space = _matrix.client.getRoomById(spaceId);
    return space?.canChangeStateEvent('m.space.child') ?? false;
  }

  /// Whether the user can edit the space name.
  bool canEditName(String spaceId) {
    final space = _matrix.client.getRoomById(spaceId);
    return space?.canChangeStateEvent('m.room.name') ?? false;
  }

  /// Whether the user can edit the space avatar.
  bool canEditAvatar(String spaceId) {
    final space = _matrix.client.getRoomById(spaceId);
    return space?.canChangeStateEvent('m.room.avatar') ?? false;
  }

  /// Whether the user can edit the space topic.
  bool canEditTopic(String spaceId) {
    final space = _matrix.client.getRoomById(spaceId);
    return space?.canChangeStateEvent('m.room.topic') ?? false;
  }

  /// Whether the user can change power levels in the space.
  bool canChangePowerLevel(String spaceId) {
    final space = _matrix.client.getRoomById(spaceId);
    return space?.canChangePowerLevel ?? false;
  }

  /// The current push rule state for the space.
  KoheraPushRuleState pushRuleState(String spaceId) {
    final space = _matrix.client.getRoomById(spaceId);
    if (space == null) return KoheraPushRuleState.notify;
    return KoheraPushRuleState.fromSdk(space.pushRuleState);
  }

  /// Sets the push rule state for the space.
  Future<void> setPushRuleState(
    String spaceId,
    KoheraPushRuleState state,
  ) async {
    final space = _matrix.client.getRoomById(spaceId);
    if (space == null) return;
    await space.setPushRuleState(_toSdkPushRuleState(state));
  }

  /// Returns the set of existing child room IDs in the space.
  Set<String> existingChildIds(String spaceId) {
    final space = _matrix.client.getRoomById(spaceId);
    if (space == null) return {};
    return space.spaceChildren.map((c) => c.roomId).whereType<String>().toSet();
  }

  /// Returns summaries of all joined rooms (for "add existing room" dialog).
  List<KoheraRoomSummary> joinedRoomSummaries() {
    return _matrix.client.rooms
        .where((r) => r.membership == Membership.join)
        .map(_matrix.selection.summaryFor)
        .toList();
  }

  /// Adds a room as a child of the space.
  Future<void> setSpaceChild(String spaceId, String childRoomId) async {
    final space = _matrix.client.getRoomById(spaceId);
    if (space == null) return;
    await space.setSpaceChild(childRoomId);
  }

  /// Invalidates the space tree cache in SelectionService.
  void invalidateSpaceTree() => _matrix.selection.invalidateSpaceTree();

  /// Marks the space and all descendant rooms as read.
  Future<void> markAsRead(String spaceId) async {
    final space = _matrix.client.getRoomById(spaceId);
    if (space == null) return;

    // Mark the space itself as read.
    final eventId = space.lastEvent?.eventId;
    if (eventId != null) {
      try {
        await space.setReadMarker(eventId);
      } catch (e) {
        debugPrint('[Kohera] Failed to mark space as read: $e');
      }
    }

    // Also mark all descendant non-space rooms as read.
    final descendantIds = <String>{};
    _collectDescendantRooms(space, descendantIds, _matrix.client);

    final roomsToMark = <({Room room, String eventId})>[];
    for (final roomId in descendantIds) {
      final room = _matrix.client.getRoomById(roomId);
      if (room == null || room.isSpace) continue;
      final childEventId = room.lastEvent?.eventId;
      if (childEventId == null) continue;
      roomsToMark.add((room: room, eventId: childEventId));
    }

    const batchSize = 5;
    for (var i = 0; i < roomsToMark.length; i += batchSize) {
      final batch =
          roomsToMark.sublist(i, min(i + batchSize, roomsToMark.length));
      await Future.wait(
        batch.map(
          (r) => r.room.setReadMarker(r.eventId).catchError((Object e) {
            debugPrint('[Kohera] Failed to mark room ${r.room.id} as read: $e');
          }),
        ),
      );
    }
  }

  /// Invites a user to the space.
  Future<void> invite(String spaceId, String mxid) async {
    final space = _matrix.client.getRoomById(spaceId);
    if (space == null) return;
    await space.invite(mxid);
  }

  /// Leaves the space, optionally leaving all child rooms too.
  /// Returns the count of child rooms that failed to leave.
  Future<int> leave(String spaceId, {bool leaveChildren = false}) async {
    final space = _matrix.client.getRoomById(spaceId);
    if (space == null) return 0;

    final childRoomIds = <String>{};
    if (leaveChildren) {
      _collectDescendantRooms(space, childRoomIds, _matrix.client);
    }

    await space.leave();
    _matrix.selection.clearSpaceSelection();

    var failCount = 0;
    for (final roomId in childRoomIds) {
      final room = _matrix.client.getRoomById(roomId);
      if (room == null || room.membership != Membership.join) continue;
      try {
        await room.leave();
      } catch (_) {
        failCount++;
      }
    }
    return failCount;
  }

  /// Sets the space name.
  Future<void> setName(String spaceId, String name) async {
    final space = _matrix.client.getRoomById(spaceId);
    if (space == null) return;
    await space.setName(name);
  }

  /// Sets the space topic/description.
  Future<void> setDescription(String spaceId, String topic) async {
    final space = _matrix.client.getRoomById(spaceId);
    if (space == null) return;
    await space.setDescription(topic);
  }

  /// Sets the space avatar.
  Future<void> setAvatar(
    String spaceId,
    Uint8List? bytes,
    String? filename,
  ) async {
    final space = _matrix.client.getRoomById(spaceId);
    if (space == null) return;
    await space.setAvatar(
      bytes == null ? null : MatrixFile(bytes: bytes, name: filename ?? ''),
    );
  }

  /// Enables encryption in the space.
  Future<void> enableEncryption(String spaceId) async {
    final space = _matrix.client.getRoomById(spaceId);
    if (space == null) return;
    await space.enableEncryption();
  }

  /// Creates a subspace as a child of [parentSpaceId].
  Future<String> createSubspace({
    required String parentSpaceId,
    required CreateSubspaceRequest request,
  }) async {
    final client = _matrix.client;

    final useRestricted = request.restrictedRoomVersion != null &&
        request.joinMode.isRestrictedFamily &&
        request.allowedSpaceIds.isNotEmpty;
    final joinRulesEvent = useRestricted
        ? _matrix.spaceAccess.buildJoinRulesStateEvent(
            request.joinMode,
            request.allowedSpaceIds,
          )
        : null;

    final roomId = await client.createRoom(
      name: request.name,
      topic: request.topic,
      creationContent: {'type': 'm.space'},
      visibility: Visibility.private,
      roomVersion: useRestricted ? request.restrictedRoomVersion : null,
      initialState: [
        ?joinRulesEvent,
      ],
      powerLevelContentOverride: {'events_default': 100},
    );

    await client
        .waitForRoomInSync(roomId, join: true)
        .timeout(const Duration(seconds: 30));

    final parentSpace = client.getRoomById(parentSpaceId);
    if (parentSpace != null) {
      await parentSpace.setSpaceChild(roomId);
    }
    _matrix.selection.invalidateSpaceTree();

    debugPrint('[Kohera] Subspace created: $roomId under $parentSpaceId');
    return roomId;
  }

  // ── Create / Join space ────────────────────────────────────

  /// Creates a new top-level space room.
  Future<String> createSpace({
    required String name,
    required bool isPublic,
    required bool enableEncryption,
    required bool enableFederation,
    String? topic,
  }) async {
    final client = _matrix.client;
    final roomId = await client.createRoom(
      name: name,
      topic: topic,
      creationContent: {
        'type': 'm.space',
        if (!enableFederation) 'm.federate': false,
      },
      initialState: [
        if (enableEncryption)
          StateEvent(
            content: {
              'algorithm': Client.supportedGroupEncryptionAlgorithms.first,
            },
            type: EventTypes.Encryption,
          ),
      ],
      visibility: isPublic ? Visibility.public : Visibility.private,
      powerLevelContentOverride: {'events_default': 100},
    );
    await client
        .waitForRoomInSync(roomId, join: true)
        .timeout(const Duration(seconds: 30));
    return roomId;
  }

  /// Joins a space by address (room ID or alias).
  /// Returns the joined room ID, or null if the room is not a space.
  Future<String?> joinSpace(String address) async {
    final client = _matrix.client;
    final roomId = await client.joinRoom(address);
    await client
        .waitForRoomInSync(roomId, join: true)
        .timeout(const Duration(seconds: 30));
    final room = client.getRoomById(roomId);
    return (room != null && room.isSpace) ? roomId : null;
  }

  /// Whether [e] is a Matrix `M_FORBIDDEN` exception.
  bool isForbiddenException(Object e) {
    return e is MatrixException && e.errcode == 'M_FORBIDDEN';
  }

  // ── Helpers ────────────────────────────────────────────────

  void _collectDescendantRooms(
    Room space,
    Set<String> ids,
    Client client,
  ) {
    for (final child in space.spaceChildren) {
      final childId = child.roomId;
      if (childId == null) continue;
      if (ids.contains(childId)) continue;
      final childRoom = client.getRoomById(childId);
      if (childRoom == null || childRoom.membership != Membership.join) {
        continue;
      }
      ids.add(childId);
      if (childRoom.isSpace) {
        _collectDescendantRooms(childRoom, ids, client);
      }
    }
  }

  PushRuleState _toSdkPushRuleState(KoheraPushRuleState state) {
    return switch (state) {
      KoheraPushRuleState.notify => PushRuleState.notify,
      KoheraPushRuleState.mentionsOnly => PushRuleState.mentionsOnly,
      KoheraPushRuleState.dontNotify => PushRuleState.dontNotify,
    };
  }
}
