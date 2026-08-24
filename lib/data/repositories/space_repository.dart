import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/models/join_mode.dart';
import 'package:kohera/core/services/sub_services/space_access_service.dart';
import 'package:kohera/data/models/kohera_push_rule_state.dart';
import 'package:kohera/data/models/kohera_room_summary.dart';
import 'package:kohera/data/resolvers/room_summary_resolver.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:matrix/matrix.dart';

class SpaceRepository extends ChangeNotifier {
  SpaceRepository({
    required MatrixClientService clientService,
    SpaceAccessService? spaceAccessOverride,
  })  : _clientService = clientService,
        _spaceAccess = spaceAccessOverride ??
            SpaceAccessService(matrixClientService: clientService);

  final MatrixClientService _clientService;
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
    if (_client.getRoomById(roomId) == null) return const [];
    final parents = _client.rooms.where(
      (candidate) =>
          candidate.isSpace &&
          candidate.id != roomId &&
          candidate.spaceChildren.any((c) => c.roomId == roomId),
    ).toList()
      ..sort(
        (a, b) =>
            a.getLocalizedDisplayname().compareTo(b.getLocalizedDisplayname()),
      );
    return parents
        .map((r) => (id: r.id, displayname: r.getLocalizedDisplayname()))
        .toList();
  }

  /// The localized display name of the space, or empty string if unknown.
  String spaceDisplayname(String spaceId) {
    final space = _client.getRoomById(spaceId);
    if (space == null) return '';
    return const RoomSummaryResolver()(space, myUserId: _client.userID)
        .displayname;
  }

  // ── Join access ────────────────────────────────────────────

  /// The join mode of [room] (public/knock/restricted/invite).
  JoinMode getJoinMode(Room room) => _spaceAccess.getJoinMode(room);

  /// The space IDs allowed to join [room] under a restricted rule.
  List<String> allowedSpaceIds(Room room) =>
      _spaceAccess.allowedSpaceIds(room);

  /// Whether [room] needs a version upgrade for a restricted join rule.
  bool needsUpgradeForRestricted(Room room, {required bool wantKnock}) =>
      _spaceAccess.needsUpgradeForRestricted(room, wantKnock: wantKnock);

  /// Applies a join [mode] to [roomId], scoped to [allowSpaceIds].
  Future<void> applyJoinMode({
    required String roomId,
    required JoinMode mode,
    List<String> allowSpaceIds = const [],
  }) =>
      _spaceAccess.applyJoinMode(
        roomId: roomId,
        mode: mode,
        allowSpaceIds: allowSpaceIds,
      );

  /// Picks the highest server room version supporting restricted joins.
  Future<String?> pickRestrictedRoomVersion({required bool wantKnock}) =>
      _spaceAccess.pickRestrictedRoomVersion(wantKnock: wantKnock);

  /// Upgrades [room] to [newVersion], returning the replacement room ID.
  Future<String> upgradeRoomTo(Room room, String newVersion) =>
      _spaceAccess.upgradeRoomTo(room, newVersion);

  /// Rewires [parents] to point at [newRoomId] in place of [oldRoomId].
  Future<void> rewireParentSpaces({
    required String oldRoomId,
    required String newRoomId,
    required List<Room> parents,
  }) =>
      _spaceAccess.rewireParentSpaces(
        oldRoomId: oldRoomId,
        newRoomId: newRoomId,
        parents: parents,
      );

  /// Builds an `m.room.join_rules` state event for [mode].
  StateEvent buildJoinRulesStateEvent(
    JoinMode mode,
    List<String> allowSpaceIds,
  ) =>
      _spaceAccess.buildJoinRulesStateEvent(mode, allowSpaceIds);

  /// All room versions advertised by the server.
  Future<List<String>> serverSupportedRoomVersions() =>
      _spaceAccess.serverSupportedRoomVersions();

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
        .map((r) => const RoomSummaryResolver()(r, myUserId: _client.userID))
        .toList();
  }

  /// Adds a room as a child of the space.
  Future<void> setSpaceChild(String spaceId, String childRoomId) async {
    final space = _client.getRoomById(spaceId);
    if (space == null) return;
    await space.setSpaceChild(childRoomId);
  }

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
