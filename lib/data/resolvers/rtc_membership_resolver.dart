import 'package:kohera/data/models/kohera_call_member_state.dart';
import 'package:kohera/data/models/kohera_livekit_focus.dart';

// ── RTC Membership Resolver ────────────────────────────────

/// Pure parsing helpers over `org.matrix.msc3401.call.member` state
/// snapshots. All inputs and outputs are SDK-free.
class RtcMembershipResolver {
  const RtcMembershipResolver();

  static final _stateKeyUserIdRegex = RegExp('_(@[^:]+:[^_]+)_');

  static String? userIdFromStateKey(String stateKey) =>
      _stateKeyUserIdRegex.firstMatch(stateKey)?.group(1);

  static bool isMembershipActive(
    Map<String, dynamic> membership,
    int originTsMs,
    int nowMs,
  ) {
    final expiresTs = membership['expires_ts'] as int?;
    if (expiresTs != null) return expiresTs > nowMs;

    final expires = membership['expires'] as int?;
    if (expires != null) return (originTsMs + expires) > nowMs;

    return false;
  }

  /// All active memberships across [states]. Handles both the legacy
  /// single-membership content shape and the `memberships` list shape.
  static List<Map<String, dynamic>> activeMemberships(
    List<KoheraCallMemberState> states,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = <Map<String, dynamic>>[];

    for (final state in states) {
      final content = state.content;
      if (content.isEmpty) continue;
      final originTs = state.originTsMs ?? now;

      final memberships = content['memberships'];
      if (memberships is List) {
        for (final mem in memberships) {
          if (mem is Map<String, dynamic> &&
              isMembershipActive(mem, originTs, now)) {
            result.add(mem);
          }
        }
      } else if (isMembershipActive(content, originTs, now)) {
        result.add(Map<String, dynamic>.from(content));
      }
    }
    return result;
  }

  static bool hasRemoteActiveCall(
    List<KoheraCallMemberState> states,
    String localUserId,
  ) {
    final localPrefix = '_${localUserId}_';
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final state in states) {
      if (state.stateKey.startsWith(localPrefix)) continue;
      final content = state.content;
      if (content.isEmpty) continue;
      if (isMembershipActive(content, state.originTsMs ?? now, now)) {
        return true;
      }
    }
    return false;
  }

  static Set<String> activeParticipantUserIds(
    List<KoheraCallMemberState> states,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final userIds = <String>{};

    for (final state in states) {
      final content = state.content;
      if (content.isEmpty) continue;
      final originTs = state.originTsMs ?? now;

      final memberships = content['memberships'];
      final bool hasActive;
      if (memberships is List) {
        hasActive = memberships.any(
          (m) =>
              m is Map<String, dynamic> && isMembershipActive(m, originTs, now),
        );
      } else {
        hasActive = isMembershipActive(content, originTs, now);
      }

      if (hasActive) {
        final userId = userIdFromStateKey(state.stateKey) ??
            (state.senderId.isNotEmpty ? state.senderId : null);
        if (userId != null) userIds.add(userId);
      }
    }
    return userIds;
  }

  static List<String> activeCallIds(List<KoheraCallMemberState> states) {
    final callIds = <String>{};
    for (final mem in activeMemberships(states)) {
      callIds.add(mem['call_id'] as String? ?? '');
    }
    return callIds.toList();
  }

  static int participantCount(
    List<KoheraCallMemberState> states,
    String groupCallId,
  ) =>
      activeMemberships(states)
          .where((m) => (m['call_id'] as String? ?? '') == groupCallId)
          .length;

  /// Selects the LiveKit focus of the oldest active membership
  /// (`focus_selection: oldest_membership`), optionally skipping
  /// memberships that belong to [excludeUserId].
  static KoheraLivekitFocus? selectOldestFocus(
    List<KoheraCallMemberState> states, {
    String? excludeUserId,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    KoheraLivekitFocus? oldestFocus;
    int? oldestTimeStamp;

    for (final state in states) {
      if (excludeUserId != null &&
          userIdFromStateKey(state.stateKey) == excludeUserId) {
        continue;
      }
      final content = state.content;
      if (content.isEmpty) continue;
      final originTs = state.originTsMs ?? now;

      final memberships = content['memberships'];
      final entries = memberships is List
          ? memberships.whereType<Map<String, dynamic>>()
          : [content];
      for (final mem in entries) {
        if (!isMembershipActive(mem, originTs, now)) continue;
        final focus = _livekitFocus(mem);
        if (focus == null) continue;
        final createdTimeStamp = mem['created_ts'] as int? ?? originTs;
        if (oldestTimeStamp == null || createdTimeStamp < oldestTimeStamp) {
          oldestTimeStamp = createdTimeStamp;
          oldestFocus = focus;
        }
      }
    }
    return oldestFocus;
  }

  static KoheraLivekitFocus? _livekitFocus(Map<String, dynamic> membership) {
    final foci = membership['foci_preferred'];
    if (foci is! List) return null;
    for (final focus in foci) {
      if (focus is Map<String, dynamic> && focus['type'] == 'livekit') {
        final url = focus['livekit_service_url'] as String?;
        if (url != null && url.isNotEmpty) {
          return KoheraLivekitFocus(
            url: url,
            alias: focus['livekit_alias'] as String? ?? '',
          );
        }
      }
    }
    return null;
  }
}
