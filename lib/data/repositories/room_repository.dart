import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/utils/known_contacts.dart' as contacts;
import 'package:kohera/data/models/kohera_push_rule_state.dart';
import 'package:kohera/data/models/kohera_room_member.dart';
import 'package:kohera/data/models/kohera_room_permissions.dart';
import 'package:kohera/data/models/kohera_room_summary.dart';
import 'package:kohera/data/models/space_node.dart';
import 'package:kohera/data/resolvers/room_member_list_resolver.dart';
import 'package:kohera/data/resolvers/room_permissions_resolver.dart';
import 'package:kohera/data/resolvers/room_summary_resolver.dart';
import 'package:matrix/encryption.dart';
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

  Future<void> invite(String roomId, String mxid) async {
    final room = _matrix.client.getRoomById(roomId);
    if (room != null) await room.invite(mxid);
  }

  Future<void> setName(String roomId, String name) async {
    final room = _matrix.client.getRoomById(roomId);
    if (room != null) await room.setName(name);
  }

  Future<void> setDescription(String roomId, String topic) async {
    final room = _matrix.client.getRoomById(roomId);
    if (room != null) await room.setDescription(topic);
  }

  Future<void> enableEncryption(String roomId) async {
    final room = _matrix.client.getRoomById(roomId);
    if (room != null) await room.enableEncryption();
  }

  Future<void> setAvatar(
    String roomId,
    Uint8List? bytes,
    String? filename,
  ) async {
    final room = _matrix.client.getRoomById(roomId);
    if (room != null) {
      await room.setAvatar(
        bytes == null ? null : MatrixFile(bytes: bytes, name: filename ?? ''),
      );
    }
  }

  Future<int?> resolveMemberCount(String roomId) async {
    if (_matrix.client.getRoomById(roomId) == null) return null;
    final members = await _matrix.client.getJoinedMembersByRoom(roomId);
    return members?.length;
  }

  Set<String> existingMemberIds(String roomId) {
    final room = _matrix.client.getRoomById(roomId);
    if (room == null) return const <String>{};
    try {
      return room.getParticipants().map((u) => u.id).toSet();
    } catch (_) {
      return const <String>{};
    }
  }

  /// The resolved avatar URI for the room, or null.
  Uri? avatarUri(String roomId) => _matrix.client.getRoomById(roomId)?.avatar;

  String? canonicalAlias(String roomId) {
    final room = _matrix.client.getRoomById(roomId);
    return room?.canonicalAlias.isNotEmpty == true
        ? room!.canonicalAlias
        : null;
  }

  bool getRoomEncrypted(String roomId) {
    final room = _matrix.client.getRoomById(roomId);
    return room?.encrypted ?? false;
  }

  bool getRoomIsFavourite(String roomId) {
    final room = _matrix.client.getRoomById(roomId);
    return room?.isFavourite ?? false;
  }

  bool getRoomCanBan(String roomId) {
    final room = _matrix.client.getRoomById(roomId);
    return room?.canBan ?? false;
  }

  bool getRoomIsDirectChat(String roomId) {
    final room = _matrix.client.getRoomById(roomId);
    return room?.isDirectChat ?? false;
  }

  String? getRoomPartnerId(String roomId) {
    final room = _matrix.client.getRoomById(roomId);
    return room?.directChatMatrixID;
  }

  int? getRoomSummaryMemberCount(String roomId) {
    final room = _matrix.client.getRoomById(roomId);
    return room?.summary.mJoinedMemberCount;
  }

  bool getRoomParticipantListComplete(String roomId) {
    final room = _matrix.client.getRoomById(roomId);
    return room?.participantListComplete ?? false;
  }

  KoheraPushRuleState getRoomPushRuleState(String roomId) {
    final room = _matrix.client.getRoomById(roomId);
    return _toKohera(room?.pushRuleState ?? PushRuleState.notify);
  }

  // ── Sync stream ──────────────────────────────────────────────

  Stream<SyncUpdate> get onSync => _matrix.client.onSync.stream;

  /// Emits when power-level events change for [roomId].
  Stream<void> powerLevelChangesFor(String roomId) {
    return onSync.where((update) {
      final stateEvents = update.rooms?.join?[roomId]?.state ?? [];
      return stateEvents.any((e) => e.type == EventTypes.RoomPowerLevels);
    });
  }

  /// Waits for the room's favourite state to match [target], or times out
  /// after 5 seconds.
  Future<void> waitForFavourite(String roomId, bool target) async {
    try {
      await onSync
          .firstWhere((_) => getRoomIsFavourite(roomId) == target)
          .timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // Best-effort wait — timeout is fine
    }
  }

  /// The event ID of the room's most recent event, or null if there is none.
  ///
  /// Used as the representative event for room-level reporting (the Matrix
  /// `/report` endpoint is per-event).
  String? lastEventId(String roomId) =>
      _matrix.client.getRoomById(roomId)?.lastEvent?.eventId;

  // ── State writes ─────────────────────────────────────────────

  /// Writes a room state event of [type] with [stateKey] to [roomId].
  Future<void> setRoomStateWithKey(
    String roomId,
    String type,
    String stateKey,
    Map<String, dynamic> content,
  ) =>
      _matrix.client.setRoomStateWithKey(roomId, type, stateKey, content);

  /// Unbans [userId] from [roomId], optionally recording a [reason].
  Future<void> unban(String roomId, String userId, {String? reason}) =>
      _matrix.client.unban(roomId, userId, reason: reason);

  /// Kicks [userId] from [roomId], optionally recording a [reason].
  Future<void> kick(String roomId, String userId, {String? reason}) =>
      _matrix.client.kick(roomId, userId, reason: reason);

  /// Bans [userId] from [roomId], optionally recording a [reason].
  Future<void> ban(String roomId, String userId, {String? reason}) =>
      _matrix.client.ban(roomId, userId, reason: reason);

  // ── Direct chats ─────────────────────────────────────────────

  /// The current user's Matrix ID.
  String? get userId => _matrix.userID;

  /// User IDs the current account has ignored, for timeline filtering.
  List<String> get ignoredUsers => _matrix.client.ignoredUsers;

  /// The account's active [Encryption] engine, or `null` when unencrypted.
  /// Consumers operate on the returned SDK object (escape hatch, #1025).
  Encryption? get encryption => _matrix.client.encryption;

  /// Reports [eventId] in [roomId] to the homeserver moderators.
  Future<void> reportEvent(String roomId, String eventId, {String? reason}) =>
      _matrix.client.reportEvent(roomId, eventId, reason: reason);

  /// Posts a read receipt for [eventId] in [roomId].
  Future<void> postReceipt(
    String roomId,
    ReceiptType type,
    String eventId, {
    String? threadId,
  }) =>
      _matrix.client.postReceipt(roomId, type, eventId, threadId: threadId);

  /// Fetches the joined members of [roomId] from the homeserver.
  Future<Map<String, RoomMember>?> getJoinedMembersByRoom(String roomId) =>
      _matrix.client.getJoinedMembersByRoom(roomId);

  /// Starts (or reuses) a direct chat with [userId], returning its room ID.
  Future<String> startDirectChat(String userId, {bool enableEncryption = true}) =>
      _matrix.client.startDirectChat(userId, enableEncryption: enableEncryption);

  /// Waits until [roomId] appears in a sync with the given membership.
  Future<void> waitForRoomInSync(String roomId, {bool join = false}) =>
      _matrix.client.waitForRoomInSync(roomId, join: join);

  /// Raw client for the cross-room message search controller, which drives the
  /// `/search` endpoint and scans encrypted rooms locally. Escape hatch pending
  /// a dedicated search repository (#1025).
  Client get searchClient => _matrix.client;

  // ── Aliases ──────────────────────────────────────────────────

  /// The local aliases published for [roomId] on the user's homeserver.
  Future<List<String>> getLocalAliases(String roomId) =>
      _matrix.client.getLocalAliases(roomId);

  /// Publishes [alias] pointing at [roomId].
  Future<void> setRoomAlias(String alias, String roomId) =>
      _matrix.client.setRoomAlias(alias, roomId);

  /// Removes the published [alias].
  Future<void> deleteRoomAlias(String alias) =>
      _matrix.client.deleteRoomAlias(alias);

  // ── Room creation ────────────────────────────────────────────

  /// Searches the user directory for [query].
  Future<List<Profile>> searchUserDirectory(String query, {int limit = 20}) async {
    final response = await _matrix.client.searchUserDirectory(query, limit: limit);
    return response.results;
  }

  /// Profiles for users with an existing direct chat.
  List<Profile> knownContacts() => contacts.knownContacts(_matrix.client);

  /// Profiles for users from group rooms, excluding [excludeMxids].
  List<Profile> roomContacts({Set<String> excludeMxids = const {}}) =>
      contacts.roomContacts(_matrix.client, excludeMxids: excludeMxids);

  /// Creates a room and returns its ID.
  Future<String> createRoom({
    String? name,
    String? topic,
    Visibility? visibility,
    String? roomVersion,
    List<StateEvent>? initialState,
    List<String>? invite,
  }) =>
      _matrix.client.createRoom(
        name: name,
        topic: topic,
        visibility: visibility,
        roomVersion: roomVersion,
        initialState: initialState,
        invite: invite,
      );

  /// Adds [childRoomId] as a child of [spaceId].
  Future<void> setSpaceChild(String spaceId, String childRoomId) async {
    final space = _matrix.client.getRoomById(spaceId);
    if (space != null) await space.setSpaceChild(childRoomId);
  }

  // ── Transitional raw room access ──────────────────────────────

  Room? rawRoom(String roomId) => _matrix.client.getRoomById(roomId);

  // ── Helpers ──────────────────────────────────────────────────

  PushRuleState _toSdkPushRuleState(KoheraPushRuleState state) {
    return switch (state) {
      KoheraPushRuleState.notify => PushRuleState.notify,
      KoheraPushRuleState.mentionsOnly => PushRuleState.mentionsOnly,
      KoheraPushRuleState.dontNotify => PushRuleState.dontNotify,
    };
  }

  KoheraPushRuleState _toKohera(PushRuleState state) => switch (state) {
        PushRuleState.notify => KoheraPushRuleState.notify,
        PushRuleState.mentionsOnly => KoheraPushRuleState.mentionsOnly,
        PushRuleState.dontNotify => KoheraPushRuleState.dontNotify,
      };

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
