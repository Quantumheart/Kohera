import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/models/join_mode.dart';
import 'package:kohera/core/services/sub_services/selection_service.dart';
import 'package:kohera/core/services/sub_services/space_access_service.dart';
import 'package:kohera/data/models/kohera_push_rule_state.dart';
import 'package:kohera/data/models/kohera_room_summary.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:matrix/matrix.dart';

class SpaceRepository extends ChangeNotifier {
  SpaceRepository({
    required MatrixClientService clientService,
    required SelectionService selection,
    required SpaceAccessService spaceAccess,
  })  : _clientService = clientService,
        _selection = selection,
        _spaceAccess = spaceAccess;

  final MatrixClientService _clientService;
  final SelectionService _selection;
  final SpaceAccessService _spaceAccess;
  bool _disposed = false;

  Client get _client => _clientService.client;

  /// Whether a space with [spaceId] is currently known to the client.
  bool spaceExists(String spaceId) =>
      _client.getRoomById(spaceId) != null;

  /// The host of the user's own homeserver, or null if unknown.
  String? get ownHomeserverHost => _client.homeserver?.host;

  /// The parent spaces of [roomId] as `(id, displayname)` records.
  List<({String id, String displayname})> parentSpaceRefs(String roomId) {
    final room = _client.getRoomById(roomId);
    if (room == null) return const [];
    return _selection
        .parentSpacesOf(room)
        .map((r) => (id: r.id, displayname: r.getLocalizedDisplayname()))
        .toList();
  }

  /// The localized display name of the space, or empty string if unknown.
  String spaceDisplayname(String spaceId) {
    final space = _client.getRoomById(spaceId);
    if (space == null) return '';
    return _selection.summaryFor(space).displayname;
  }

  // ── Permissions ────────────────────────────────────────────

  /// Whether the user can invite people to the space.
  bool canInvite(String spaceId) {
    final space = _client.getRoomById(spaceId);
    return space?.canInvite ?? false;
  }

  /// Whether the user can manage space children (add/remove rooms).
  bool canManageChildren(String spaceId) {
    final space = _client.getRoomById(spaceId);
    return space?.canChangeStateEvent('m.space.child') ?? false;
  }

  /// Whether the user can edit the space name.
  bool canEditName(String spaceId) {
    final space = _client.getRoomById(spaceId);
    return space?.canChangeStateEvent('m.room.name') ?? false;
  }

  /// Whether the user can edit the space avatar.
  bool canEditAvatar(String spaceId) {
    final space = _client.getRoomById(spaceId);
    return space?.canChangeStateEvent('m.room.avatar') ?? false;
  }

  /// Whether the user can edit the space topic.
  bool canEditTopic(String spaceId) {
    final space = _client.getRoomById(spaceId);
    return space?.canChangeStateEvent('m.room.topic') ?? false;
  }

  /// Whether the user can change power levels in the space.
  bool canChangePowerLevel(String spaceId) {
    final space = _client.getRoomById(spaceId);
    return space?.canChangePowerLevel ?? false;
  }

  // ── Notifications ──────────────────────────────────────────

  /// The current push rule state for the space.
  KoheraPushRuleState pushRuleState(String spaceId) {
    final space = _client.getRoomById(spaceId);
    if (space == null) return KoheraPushRuleState.notify;
    return KoheraPushRuleState.fromSdk(space.pushRuleState);
  }

  /// Sets the push rule state for the space.
  Future<void> setPushRuleState(
    String spaceId,
    KoheraPushRuleState state,
  ) async {
    final space = _client.getRoomById(spaceId);
    if (space == null) return;
    await space.setPushRuleState(_toSdkPushRuleState(state));
  }

  // ── Children ───────────────────────────────────────────────

  /// Returns the set of existing child room IDs in the space.
  Set<String> existingChildIds(String spaceId) {
    final space = _client.getRoomById(spaceId);
    if (space == null) return {};
    return space.spaceChildren.map((c) => c.roomId).whereType<String>().toSet();
  }

  /// Returns summaries of all joined rooms (for "add existing room" dialog).
  List<KoheraRoomSummary> joinedRoomSummaries() {
    return _client.rooms
        .where((r) => r.membership == Membership.join)
        .map(_selection.summaryFor)
        .toList();
  }

  /// Adds a room as a child of the space.
  Future<void> setSpaceChild(String spaceId, String childRoomId) async {
    final space = _client.getRoomById(spaceId);
    if (space == null) return;
    await space.setSpaceChild(childRoomId);
  }

  /// Invalidates the space tree cache in SelectionService.
  void invalidateSpaceTree() => _selection.invalidateSpaceTree();

  /// Marks the space and all descendant rooms as read.
  Future<void> markAsRead(String spaceId) async {
    final space = _client.getRoomById(spaceId);
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
    _collectDescendantRooms(space, descendantIds, _client);

    final roomsToMark = <({Room room, String eventId})>[];
    for (final roomId in descendantIds) {
      final room = _client.getRoomById(roomId);
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

  // ── Space editing ──────────────────────────────────────────

  /// Invites a user to the space.
  Future<void> invite(String spaceId, String mxid) async {
    final space = _client.getRoomById(spaceId);
    if (space == null) return;
    await space.invite(mxid);
  }

  /// Leaves the space, optionally leaving all child rooms too.
  /// Returns the count of child rooms that failed to leave.
  Future<int> leave(String spaceId, {bool leaveChildren = false}) async {
    final space = _client.getRoomById(spaceId);
    if (space == null) return 0;

    final childRoomIds = <String>{};
    if (leaveChildren) {
      _collectDescendantRooms(space, childRoomIds, _client);
    }

    await space.leave();
    _selection.clearSpaceSelection();

    var failCount = 0;
    for (final roomId in childRoomIds) {
      final room = _client.getRoomById(roomId);
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
    final space = _client.getRoomById(spaceId);
    if (space == null) return;
    await space.setName(name);
  }

  /// Sets the space topic/description.
  Future<void> setDescription(String spaceId, String topic) async {
    final space = _client.getRoomById(spaceId);
    if (space == null) return;
    await space.setDescription(topic);
  }

  /// Sets the space avatar.
  Future<void> setAvatar(
    String spaceId,
    Uint8List? bytes,
    String? filename,
  ) async {
    final space = _client.getRoomById(spaceId);
    if (space == null) return;
    await space.setAvatar(
      bytes == null ? null : MatrixFile(bytes: bytes, name: filename ?? ''),
    );
  }

  /// Enables encryption in the space.
  Future<void> enableEncryption(String spaceId) async {
    final space = _client.getRoomById(spaceId);
    if (space == null) return;
    await space.enableEncryption();
  }

  // ── Create / Join space ────────────────────────────────────

  /// Creates a subspace as a child of [parentSpaceId].
  Future<String> createSubspace({
    required String parentSpaceId,
    required String name,
    required JoinMode joinMode,
    required List<String> allowedSpaceIds,
    String? topic,
    String? restrictedRoomVersion,
  }) async {
    final client = _client;

    final useRestricted = restrictedRoomVersion != null &&
        joinMode.isRestrictedFamily &&
        allowedSpaceIds.isNotEmpty;
    final joinRulesEvent = useRestricted
        ? _spaceAccess.buildJoinRulesStateEvent(
            joinMode,
            allowedSpaceIds,
          )
        : null;

    final roomId = await client.createRoom(
      name: name,
      topic: topic,
      creationContent: {'type': 'm.space'},
      visibility: Visibility.private,
      roomVersion: useRestricted ? restrictedRoomVersion : null,
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
    _selection.invalidateSpaceTree();

    debugPrint('[Kohera] Subspace created: $roomId under $parentSpaceId');
    return roomId;
  }

  /// Creates a new top-level space room.
  Future<String> createSpace({
    required String name,
    required bool isPublic,
    required bool enableEncryption,
    required bool enableFederation,
    String? topic,
  }) async {
    final client = _client;
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

  /// Joins a room or space by address (room ID or alias), with optional via
  /// servers (e.g. extracted from a `matrix.to` link).
  ///
  /// Returns the joined room ID and whether the room is a space.
  Future<JoinByAddressResult> joinByAddress(
    String address, {
    List<String>? via,
  }) async {
    final client = _client;
    final roomId = await client.joinRoom(address, via: via);
    await client
        .waitForRoomInSync(roomId, join: true)
        .timeout(const Duration(seconds: 30));
    final room = client.getRoomById(roomId);
    return JoinByAddressResult(
      roomId: roomId,
      isSpace: room?.isSpace ?? false,
    );
  }

  /// Joins a space by address (room ID or alias).
  /// Returns the joined room ID, or null if the room is not a space.
  Future<String?> joinSpace(String address) async {
    final result = await joinByAddress(address);
    return result.isSpace ? result.roomId : null;
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

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Result of joining a room by address.
class JoinByAddressResult {
  const JoinByAddressResult({required this.roomId, required this.isSpace});

  /// The joined room ID.
  final String roomId;

  /// Whether the joined room is a space.
  final bool isSpace;
}
