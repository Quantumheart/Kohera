import 'package:kohera/core/models/join_mode.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/utils/known_contacts.dart' as contacts;
import 'package:kohera/shared/models/kohera_user_summary.dart';
import 'package:matrix/matrix.dart';

/// Service layer that wraps all SDK calls needed by the room creation and
/// DM dialogs. Converts SDK `Profile` to Kohera-owned `KoheraUserSummary`.
///
/// Widgets call these methods with simple types (`String`, `bool`, etc.)
/// and receive Kohera-owned types. The SDK `Client` is never exposed.
class RoomCreationService {
  RoomCreationService(this._matrix);

  final MatrixService _matrix;

  /// Searches the user directory for [query], returning `KoheraUserSummary`.
  Future<List<KoheraUserSummary>> searchUserDirectory(String query) async {
    final response = await _matrix.client.searchUserDirectory(query, limit: 20);
    return response.results.map(_toSummary).toList(growable: false);
  }

  /// Returns known contacts (from existing DM rooms) as `KoheraUserSummary`.
  List<KoheraUserSummary> knownContacts() {
    return contacts
        .knownContacts(_matrix.client)
        .map(_toSummary)
        .toList(growable: false);
  }

  /// Returns contacts from group rooms (non-DM), excluding [excludeMxids].
  List<KoheraUserSummary> roomContacts({Set<String> excludeMxids = const {}}) {
    return contacts
        .roomContacts(_matrix.client, excludeMxids: excludeMxids)
        .map(_toSummary)
        .toList(growable: false);
  }

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
    dynamic joinRulesEvent,
  }) async {
    final client = _matrix.client;
    return client.createRoom(
      name: name,
      topic: topic,
      visibility: isPublic ? Visibility.public : Visibility.private,
      roomVersion: roomVersion,
      initialState: [
        if (enableEncryption)
          StateEvent(
            content: {
              'algorithm': Client.supportedGroupEncryptionAlgorithms.first,
            },
            type: EventTypes.Encryption,
          ),
        if (joinRulesEvent != null) joinRulesEvent as StateEvent,
      ],
      invite: invite,
    );
  }

  /// Waits for a room to appear in sync after creation.
  Future<void> waitForRoomInSync(String roomId) async {
    await _matrix.client
        .waitForRoomInSync(roomId, join: true)
        .timeout(const Duration(seconds: 30));
  }

  /// Starts a direct chat with [userId].
  Future<String> startDirectChat(
    String userId, {
    bool enableEncryption = true,
  }) async {
    return _matrix.client
        .startDirectChat(userId, enableEncryption: enableEncryption);
  }

  /// Checks if a room is already in the local state (avoids hanging
  /// `waitForRoomInSync` for existing DMs).
  bool isRoomInSync(String roomId) =>
      _matrix.client.getRoomById(roomId) != null;

  /// Builds a join-rules state event for restricted join modes.
  dynamic buildJoinRulesStateEvent(
    JoinMode mode,
    List<String> allowedSpaceIds,
  ) {
    return _matrix.spaceAccess.buildJoinRulesStateEvent(mode, allowedSpaceIds);
  }

  /// Picks a room version that supports restricted join rules.
  Future<String?> pickRestrictedRoomVersion({required bool wantKnock}) async {
    return _matrix.spaceAccess.pickRestrictedRoomVersion(wantKnock: wantKnock);
  }

  /// Returns all server-supported room versions (for debugging).
  Future<List<String>> serverSupportedRoomVersions() async {
    return _matrix.spaceAccess.serverSupportedRoomVersions();
  }

  /// Adds a room as a child of [spaceId].
  Future<void> setSpaceChild(String spaceId, String childRoomId) async {
    final space = _matrix.client.getRoomById(spaceId);
    if (space != null) await space.setSpaceChild(childRoomId);
  }

  /// Invalidates the space tree cache.
  void invalidateSpaceTree() => _matrix.selection.invalidateSpaceTree();

  /// Selects a room in the SelectionService.
  void selectRoom(String roomId) => _matrix.selection.selectRoom(roomId);

  KoheraUserSummary _toSummary(Profile p) => KoheraUserSummary(
        userId: p.userId,
        displayname: p.displayName ?? p.userId,
        avatarUrl: p.avatarUrl?.toString(),
      );
}
