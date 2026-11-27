import 'package:kohera/data/models/call_constants.dart';
import 'package:kohera/data/models/kohera_call_member_state.dart';
import 'package:kohera/data/models/kohera_call_member_update.dart';
import 'package:kohera/data/models/kohera_caller_profile.dart';
import 'package:kohera/data/models/kohera_livekit_focus.dart';
import 'package:kohera/data/models/kohera_open_id_token.dart';
import 'package:kohera/data/models/kohera_signaling_event.dart';
import 'package:kohera/data/resolvers/rtc_membership_resolver.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:matrix/matrix.dart';

// ── Call Repository ────────────────────────────────────────

/// SDK boundary for RTC calling: membership state, LiveKit
/// authentication, and call signaling. Feature code consumes only
/// SDK-free types from this repository.
class CallRepository {
  CallRepository({required MatrixClientService clientService})
      : _clientService = clientService;

  final MatrixClientService _clientService;

  Client get _client => _clientService.client;

  String? get userId => _client.userID;

  String? get deviceId => _client.deviceID;

  /// The `org.matrix.msc3401.call.member` state key for this device.
  String get membershipStateKey => '_${_client.userID!}_${_client.deviceID!}_m.call';

  // ── Membership state reads ───────────────────────────────

  List<KoheraCallMemberState> _memberStates(String roomId) {
    final room = _client.getRoomById(roomId);
    if (room == null) return const [];
    final states = room.states[callMemberEventType];
    if (states == null) return const [];
    return [
      for (final entry in states.entries)
        KoheraCallMemberState(
          stateKey: entry.key,
          senderId: entry.value.senderId,
          content: entry.value.content,
          originTsMs: entry.value is Event
              ? (entry.value as Event).originServerTs.millisecondsSinceEpoch
              : null,
        ),
    ];
  }

  bool roomHasActiveCall(String roomId) =>
      RtcMembershipResolver.activeMemberships(_memberStates(roomId))
          .isNotEmpty;

  bool roomHasRemoteActiveCall(String roomId) {
    final userId = _client.userID;
    if (userId == null) return false;
    return RtcMembershipResolver.hasRemoteActiveCall(
      _memberStates(roomId),
      userId,
    );
  }

  Set<String> activeCallParticipantUserIds(String roomId) =>
      RtcMembershipResolver.activeParticipantUserIds(_memberStates(roomId));

  List<String> activeCallIdsForRoom(String roomId) =>
      RtcMembershipResolver.activeCallIds(_memberStates(roomId));

  int callParticipantCount(String roomId, String groupCallId) =>
      RtcMembershipResolver.participantCount(
        _memberStates(roomId),
        groupCallId,
      );

  KoheraLivekitFocus? selectOldestFocus(
    String roomId, {
    String? excludeUserId,
  }) =>
      RtcMembershipResolver.selectOldestFocus(
        _memberStates(roomId),
        excludeUserId: excludeUserId,
      );

  bool isDirectChat(String roomId) =>
      _client.getRoomById(roomId)?.isDirectChat ?? false;

  bool roomExists(String roomId) => _client.getRoomById(roomId) != null;

  /// The localized display name of [roomId], or a placeholder when the
  /// room is unknown.
  String displayNameFor(String roomId) =>
      _client.getRoomById(roomId)?.getLocalizedDisplayname() ??
      'Unknown room';

  /// The LiveKit alias for [roomId]: the canonical alias when set,
  /// otherwise the room id.
  String livekitAliasFor(String roomId) {
    final room = _client.getRoomById(roomId);
    if (room == null) return roomId;
    return room.canonicalAlias.isNotEmpty ? room.canonicalAlias : room.id;
  }

  /// Display name and avatar for [userId] in [roomId].
  KoheraCallerProfile callerProfileFor(String roomId, String userId) {
    final room = _client.getRoomById(roomId);
    if (room == null) {
      return KoheraCallerProfile(displayName: userId);
    }
    final sender = room.unsafeGetUserFromMemoryOrFallback(userId);
    return KoheraCallerProfile(
      displayName: sender.calcDisplayname(),
      avatarUrl: sender.avatarUrl,
    );
  }

  /// The origin timestamp in milliseconds of the call-member state event
  /// under [stateKey] in [roomId], or null when unknown.
  int? callMemberOriginTs(String roomId, String stateKey) {
    final stateEvent =
        _client.getRoomById(roomId)?.states[callMemberEventType]?[stateKey];
    if (stateEvent is! Event) return null;
    return stateEvent.originServerTs.millisecondsSinceEpoch;
  }

  /// Avatar URL for [userId] in [roomId], or null when unknown.
  Uri? avatarUrlFor(String roomId, String userId) => _client
      .getRoomById(roomId)
      ?.unsafeGetUserFromMemoryOrFallback(userId)
      .avatarUrl;

  // ── Membership state writes ──────────────────────────────

  /// Publishes this device's call membership in [roomId].
  Future<void> joinCallMembership(
    String roomId,
    String livekitAlias, {
    required String livekitServiceUrl,
    bool isVideo = false,
    int expiresMs = membershipExpiresMs,
    int? createdTimeStamp,
  }) async {
    await _client.setRoomStateWithKey(
      roomId,
      callMemberEventType,
      membershipStateKey,
      makeMembershipContent(
        livekitServiceUrl,
        livekitAlias,
        isVideo: isVideo,
        expiresMs: expiresMs,
        createdTimeStamp: createdTimeStamp,
      ),
    );
  }

  /// Clears this device's call membership in [roomId].
  Future<void> leaveCallMembership(String roomId) async {
    await _client.setRoomStateWithKey(
      roomId,
      callMemberEventType,
      membershipStateKey,
      {},
    );
  }

  /// The membership content for this device.
  Map<String, dynamic> makeMembershipContent(
    String livekitServiceUrl,
    String livekitAlias, {
    bool isVideo = false,
    int expiresMs = membershipExpiresMs,
    int? createdTimeStamp,
  }) =>
      {
        'application': 'm.call',
        'call_id': '',
        'scope': 'm.room',
        'device_id': _client.deviceID,
        'expires': expiresMs,
        'created_ts': ?createdTimeStamp,
        kIoKoheraIsVideo: isVideo,
        'focus_active': {
          'type': 'livekit',
          'focus_selection': 'oldest_membership',
        },
        'foci_preferred': [
          {
            'type': 'livekit',
            'livekit_service_url': livekitServiceUrl,
            'livekit_alias': livekitAlias,
          },
        ],
      };

  // ── LiveKit authentication ───────────────────────────────

  /// Requests an OpenID token for LiveKit service authentication.
  Future<KoheraOpenIdToken> requestOpenIdToken() async {
    final token = await _client.requestOpenIdToken(_client.userID!, {});
    return KoheraOpenIdToken(
      accessToken: token.accessToken,
      tokenType: token.tokenType,
      matrixServerName: token.matrixServerName,
      expiresIn: token.expiresIn,
    );
  }

  /// The LiveKit service URL from `.well-known/matrix/client`
  /// (`org.matrix.msc4143.rtc_foci`), or null when not configured.
  Future<String?> livekitServiceUrlFromWellknown() async {
    final wellKnown = await _client.getWellknown();
    final fociList =
        wellKnown.additionalProperties['org.matrix.msc4143.rtc_foci'] as List?;
    if (fociList == null) return null;
    for (final foci in fociList) {
      if (foci is Map<String, Object?> && foci['type'] == 'livekit') {
        final serviceUrl = foci['livekit_service_url'] as String?;
        if (serviceUrl != null) return serviceUrl;
      }
    }
    return null;
  }

  // ── Signaling streams ────────────────────────────────────

  /// Emits when any `org.matrix.msc3401.call.member` state changes.
  Stream<KoheraCallMemberUpdate> get onCallMemberState =>
      _client.onRoomState.stream
          .where((update) => update.state.type == callMemberEventType)
          .map((update) => KoheraCallMemberUpdate(
                roomId: update.roomId,
                stateKey: update.state.stateKey,
                content: update.state.content,
              ));

  /// Legacy `m.call.invite` attempts in direct chats from other users,
  /// rendered as missed-call markers.
  Stream<KoheraSignalingEvent> get legacyCallAttempts =>
      _client.onTimelineEvent.stream
          .where((event) =>
              event.type == kCallInvite &&
              event.roomId != null &&
              event.senderId != _client.userID &&
              event.room.isDirectChat)
          .map((event) => KoheraLegacyCallAttempt(
                roomId: event.roomId!,
                senderId: event.senderId,
              ));
}
