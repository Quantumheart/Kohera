import 'package:flutter/foundation.dart';

// ── KoheraRoomMember ──────────────────────────────────────────

/// A room member with pre-computed display fields and power level.
///
/// Composes the fields of [KoheraUserSummary] (userId, displayname,
/// avatarUrl) and adds `membership` and `powerLevel`. Created by
/// [RoomMemberListResolver] at the conversion boundary from
/// `matrix_sdk.User` + `Room.getPowerLevelByUserId`.
///
/// This model replaces the simple `KoheraRoomMember` that was inline in
/// `kohera_room_permissions.dart` — it adds `avatarUrl` and `membership`
/// fields needed by the member list and member sheet dialog.
@immutable
class KoheraRoomMember {
  const KoheraRoomMember({
    required this.userId,
    required this.displayname,
    required this.membership,
    required this.powerLevel,
    this.avatarUrl,
  });

  /// The Matrix user ID (e.g. `@alice:example.com`).
  final String userId;

  /// The resolved display name (never null — falls back to userId).
  final String displayname;

  /// The `mxc://` avatar URI as a string, or `null` if no avatar.
  final String? avatarUrl;

  /// Membership state as a string: 'join', 'ban', 'leave', 'invite'.
  final String membership;

  /// The user's power level in this room.
  final int powerLevel;

  /// Convenience: whether this member is banned.
  bool get isBanned => membership == 'ban';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KoheraRoomMember && userId == other.userId;

  @override
  int get hashCode => userId.hashCode;

  KoheraRoomMember copyWith({
    String? userId,
    String? displayname,
    String? avatarUrl,
    String? membership,
    int? powerLevel,
  }) =>
      KoheraRoomMember(
        userId: userId ?? this.userId,
        displayname: displayname ?? this.displayname,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        membership: membership ?? this.membership,
        powerLevel: powerLevel ?? this.powerLevel,
      );

  @override
  String toString() =>
      'KoheraRoomMember(userId: $userId, displayname: $displayname, '
      'avatarUrl: $avatarUrl, membership: $membership, '
      'powerLevel: $powerLevel)';
}

// ── KoheraRoomMemberList ──────────────────────────────────────

/// A pre-computed list of room members.
///
/// Created by [RoomMemberListResolver] at the conversion boundary.
/// Widgets below the boundary consume this model — never `Room` directly.
@immutable
class KoheraRoomMemberList {
  const KoheraRoomMemberList({
    required this.members,
    required this.participantListComplete,
    required this.memberCount,
  });

  /// The member entries, sorted by power level (admins first, then mods,
  /// then alphabetical).
  final List<KoheraRoomMember> members;

  /// Whether the participant list is complete (all members loaded from
  /// the server).
  final bool participantListComplete;

  /// The joined member count from `room.summary.mJoinedMemberCount`.
  final int memberCount;

  bool get isEmpty => members.isEmpty;
  bool get isNotEmpty => members.isNotEmpty;

  @override
  String toString() =>
      'KoheraRoomMemberList(${members.length} members, '
      'complete: $participantListComplete, count: $memberCount)';
}
