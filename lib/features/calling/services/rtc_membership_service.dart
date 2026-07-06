import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kohera/shared/models/call_constants.dart';
import 'package:matrix/matrix.dart';

// ── Constants ──────────────────────────────────────────────

const callMemberEventType = 'org.matrix.msc3401.call.member';
const membershipExpiresMs = 14400000;
const membershipRenewalInterval = Duration(minutes: 5);

// ── RTC Membership Service ─────────────────────────────────

class RtcMembershipService {
  RtcMembershipService({required Client client}) : _client = client;

  Client _client;

  void updateClient(Client client) => _client = client;

  Timer? _membershipRenewalTimer;

  String get membershipStateKey =>
      '_${_client.userID!}_${_client.deviceID!}_m.call';

  Map<String, dynamic> makeMembershipContent(
    String livekitServiceUrl,
    String livekitAlias, {
    bool isVideo = false,
    int expiresMs = membershipExpiresMs,
    int? createdTimeStamp,
  }) => {
    'application': 'm.call',
    'call_id': '',
    'scope': 'm.room',
    'device_id': _client.deviceID,
    'expires': expiresMs,
    if (createdTimeStamp != null) 'created_ts': createdTimeStamp,
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

  Future<void> sendMembershipEvent(
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

  Future<void> removeMembershipEvent(String roomId) async {
    await _client.setRoomStateWithKey(
      roomId,
      callMemberEventType,
      membershipStateKey,
      {},
    );
  }

  void startMembershipRenewal(
    String roomId,
    String livekitAlias, {
    required String livekitServiceUrl,
    bool isVideo = false,
    int? createdTimeStamp,
  }) {
    cancelMembershipRenewal();
    _membershipRenewalTimer = Timer.periodic(
      membershipRenewalInterval,
      (_) => sendMembershipEvent(
        roomId,
        livekitAlias,
        livekitServiceUrl: livekitServiceUrl,
        isVideo: isVideo,
        createdTimeStamp: createdTimeStamp,
      ).catchError(
        (Object e) => debugPrint('[Kohera] Failed to renew membership: $e'),
      ),
    );
  }

  void cancelMembershipRenewal() {
    _membershipRenewalTimer?.cancel();
    _membershipRenewalTimer = null;
  }

  // ── Membership Queries ──────────────────────────────────────

  static bool roomHasActiveCall(Client client, String roomId) {
    final room = client.getRoomById(roomId);
    if (room == null) return false;
    return _getActiveRtcMemberships(room).isNotEmpty;
  }

  static bool roomHasRemoteActiveCall(Client client, String roomId) {
    final room = client.getRoomById(roomId);
    if (room == null) return false;
    final states = room.states[callMemberEventType];
    if (states == null) return false;
    final localPrefix = '_${client.userID!}_';
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in states.entries) {
      if (entry.key.startsWith(localPrefix)) continue;
      final content = entry.value.content;
      if (content.isEmpty) continue;
      final originTs = entry.value is Event
          ? (entry.value as Event).originServerTs.millisecondsSinceEpoch
          : now;
      if (isMembershipActive(content, originTs, now)) return true;
    }
    return false;
  }

  static final _stateKeyUserIdRegex = RegExp('_(@[^:]+:[^_]+)_');

  static String? userIdFromStateKey(String stateKey) =>
      _stateKeyUserIdRegex.firstMatch(stateKey)?.group(1);

  static Set<String> activeCallParticipantUserIds(
    Client client,
    String roomId,
  ) {
    final room = client.getRoomById(roomId);
    if (room == null) return const {};
    final states = room.states[callMemberEventType];
    if (states == null) return const {};

    final now = DateTime.now().millisecondsSinceEpoch;
    final userIds = <String>{};

    for (final entry in states.entries) {
      final stateEvent = entry.value;
      final content = stateEvent.content;
      if (content.isEmpty) continue;
      final originTs = stateEvent is Event
          ? stateEvent.originServerTs.millisecondsSinceEpoch
          : now;

      final memberships = content['memberships'];
      bool hasActive;
      if (memberships is List) {
        hasActive = memberships.any(
          (m) =>
              m is Map<String, dynamic> &&
              isMembershipActive(m, originTs, now),
        );
      } else {
        hasActive = isMembershipActive(content, originTs, now);
      }

      if (hasActive) {
        final userId = userIdFromStateKey(entry.key) ??
            (stateEvent.senderId.isNotEmpty ? stateEvent.senderId : null);
        if (userId != null) userIds.add(userId);
      }
    }
    return userIds;
  }

  static List<String> activeCallIdsForRoom(Client client, String roomId) {
    final room = client.getRoomById(roomId);
    if (room == null) return const [];
    final memberships = _getActiveRtcMemberships(room);
    final callIds = <String>{};
    for (final mem in memberships) {
      final callId = mem['call_id'] as String? ?? '';
      callIds.add(callId);
    }
    return callIds.toList();
  }

  static int callParticipantCount(
    Client client,
    String roomId,
    String groupCallId,
  ) {
    final room = client.getRoomById(roomId);
    if (room == null) return 0;
    final memberships = _getActiveRtcMemberships(room);
    return memberships
        .where((m) => (m['call_id'] as String? ?? '') == groupCallId)
        .length;
  }

  // ── Focus Selection (oldest_membership) ─────────────────────

  static ({String url, String alias})? _livekitFocus(Map<String, dynamic> mem) {
    final foci = mem['foci_preferred'];
    if (foci is! List) return null;
    for (final focus in foci) {
      if (focus is Map<String, dynamic> && focus['type'] == 'livekit') {
        final url = focus['livekit_service_url'] as String?;
        if (url != null && url.isNotEmpty) {
          return (url: url, alias: focus['livekit_alias'] as String? ?? '');
        }
      }
    }
    return null;
  }

  static int _membershipCreatedTimeStamp(
    Map<String, dynamic> mem,
    int originTs,
  ) =>
      mem['created_ts'] as int? ?? originTs;

  static ({String url, String alias})? selectOldestFocus(
    Client client,
    String roomId, {
    String? excludeUserId,
  }) {
    final room = client.getRoomById(roomId);
    if (room == null) return null;
    final states = room.states[callMemberEventType];
    if (states == null) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    ({String url, String alias})? oldestFocus;
    int? oldestTimeStamp;

    for (final entry in states.entries) {
      if (excludeUserId != null &&
          userIdFromStateKey(entry.key) == excludeUserId) {
        continue;
      }
      final stateEvent = entry.value;
      final content = stateEvent.content;
      if (content.isEmpty) continue;
      final originTs = stateEvent is Event
          ? stateEvent.originServerTs.millisecondsSinceEpoch
          : now;

      final memberships = content['memberships'];
      final entries = memberships is List
          ? memberships.whereType<Map<String, dynamic>>()
          : [content];
      for (final mem in entries) {
        if (!isMembershipActive(mem, originTs, now)) continue;
        final focus = _livekitFocus(mem);
        if (focus == null) continue;
        final createdTimeStamp = _membershipCreatedTimeStamp(mem, originTs);
        if (oldestTimeStamp == null || createdTimeStamp < oldestTimeStamp) {
          oldestTimeStamp = createdTimeStamp;
          oldestFocus = focus;
        }
      }
    }
    return oldestFocus;
  }

  static List<Map<String, dynamic>> _getActiveRtcMemberships(Room room) {
    final states = room.states[callMemberEventType];
    if (states == null) return const [];

    final now = DateTime.now().millisecondsSinceEpoch;
    final result = <Map<String, dynamic>>[];

    for (final stateEvent in states.values) {
      final content = stateEvent.content;
      if (content.isEmpty) continue;

      final originTs = stateEvent is Event
          ? stateEvent.originServerTs.millisecondsSinceEpoch
          : now;

      final memberships = content['memberships'];
      if (memberships is List) {
        for (final mem in memberships) {
          if (mem is Map<String, dynamic> &&
              isMembershipActive(mem, originTs, now)) {
            result.add(mem);
          }
        }
      } else {
        if (isMembershipActive(content, originTs, now)) {
          result.add(Map<String, dynamic>.from(content));
        }
      }
    }
    return result;
  }

  static bool isMembershipActive(
    Map<String, dynamic> mem,
    int originTs,
    int nowMs,
  ) {
    final expiresTs = mem['expires_ts'] as int?;
    if (expiresTs != null) return expiresTs > nowMs;

    final expires = mem['expires'] as int?;
    if (expires != null) return (originTs + expires) > nowMs;

    return false;
  }
}
