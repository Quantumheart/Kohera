import 'package:kohera/core/models/join_mode.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/data/models/kohera_user_summary.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/data/repositories/space_repository.dart';
import 'package:kohera/data/repositories/user_repository.dart';

/// Service layer that wraps all SDK calls needed by the room creation and
/// DM dialogs. Widgets call these methods with simple types (`String`,
/// `bool`, etc.) and receive Kohera-owned types. SDK access routes through
/// [RoomRepository], [UserRepository], and [SpaceRepository].
class RoomCreationService {
  RoomCreationService(this._matrix, this._rooms, this._users, this._spaces);

  final MatrixService _matrix;
  final RoomRepository _rooms;
  final UserRepository _users;
  final SpaceRepository _spaces;

  /// Searches the user directory for [query], returning `KoheraUserSummary`.
  Future<List<KoheraUserSummary>> searchUserDirectory(String query) =>
      _users.searchUserDirectory(query);

  /// Returns known contacts (from existing DM rooms) as `KoheraUserSummary`.
  List<KoheraUserSummary> knownContacts() => _users.knownContacts();

  /// Returns contacts from group rooms (non-DM), excluding [excludeMxids].
  List<KoheraUserSummary> roomContacts({Set<String> excludeMxids = const {}}) =>
      _users.roomContacts(excludeMxids: excludeMxids);

  /// Creates a new room with the given parameters.
  ///
  /// [joinRulesEvent] is an optional pre-built join-rules state event
  /// (from `SpaceAccessService.buildJoinRulesStateEvent`). When non-null,
  /// it is included in the initial state events.
  Future<String> createRoom({
    required String name,
    required bool isPublic,
    required bool enableEncryption,
    String? topic,
    List<String>? invite,
    String? roomVersion,
    Object? joinRulesEvent,
  }) async {
    return _rooms.createRoom(
      name: name,
      topic: topic,
      isPublic: isPublic,
      roomVersion: roomVersion,
      enableEncryption: enableEncryption,
      joinRulesEvent: joinRulesEvent,
      invite: invite,
    );
  }

  /// Waits for a room to appear in sync after creation.
  Future<void> waitForRoomInSync(String roomId) async {
    await _rooms
        .waitForRoomInSync(roomId, join: true)
        .timeout(const Duration(seconds: 30));
  }

  /// Starts a direct chat with [userId].
  Future<String> startDirectChat(
    String userId, {
    bool enableEncryption = true,
  }) async {
    return _rooms.startDirectChat(userId, enableEncryption: enableEncryption);
  }

  /// Checks if a room is already in the local state (avoids hanging
  /// `waitForRoomInSync` for existing DMs).
  bool isRoomInSync(String roomId) => _rooms.roomExists(roomId);

  /// Builds a join-rules state event for restricted join modes.
  dynamic buildJoinRulesStateEvent(
    JoinMode mode,
    List<String> allowedSpaceIds,
  ) {
    return _spaces.buildJoinRulesStateEvent(mode, allowedSpaceIds);
  }

  /// Picks a room version that supports restricted join rules.
  Future<String?> pickRestrictedRoomVersion({required bool wantKnock}) async {
    return _spaces.pickRestrictedRoomVersion(wantKnock: wantKnock);
  }

  /// Returns all server-supported room versions (for debugging).
  Future<List<String>> serverSupportedRoomVersions() async {
    return _spaces.serverSupportedRoomVersions();
  }

  /// Adds a room as a child of [spaceId].
  Future<void> setSpaceChild(String spaceId, String childRoomId) =>
      _rooms.setSpaceChild(spaceId, childRoomId);

  /// Invalidates the space tree cache.
  void invalidateSpaceTree() => _matrix.spaceTree.invalidateSpaceTree();

  /// Selects a room in the SelectionService.
  void selectRoom(String roomId) => _matrix.selectionController.selectRoom(roomId);
}
