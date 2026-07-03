import 'package:flutter/foundation.dart';

// ── KoheraJoinRule ────────────────────────────────────────────

/// Kohera-owned representation of a Matrix `join_rule` value.
///
/// Mirrors the SDK `JoinRules` enum but carries no SDK dependency.
enum KoheraJoinRule {
  public,
  invite,
  knock,
  restricted;

  /// Human-readable label for dropdowns and chips.
  String get label => switch (this) {
        public => 'Public',
        invite => 'Invite-only',
        knock => 'Knock',
        restricted => 'Restricted',
      };

  /// Longer description used in confirmation dialogs.
  String get description => switch (this) {
        public =>
          'Anyone can join without an invitation. The room will be publicly '
              'discoverable.',
        invite => 'Only users invited by a member can join.',
        knock =>
          'Users can request to join. A moderator must approve each request.',
        restricted => 'Users in a linked space can join automatically.',
      };

  /// Wire value for the `join_rule` field in `m.room.join_rules`.
  String get wire => switch (this) {
        public => 'public',
        invite => 'invite',
        knock => 'knock',
        restricted => 'restricted',
      };
}

// ── KoheraRoomMember ──────────────────────────────────────────

/// A room participant with their computed power level.
///
/// Pre-computed at the conversion boundary from
/// `Room.getParticipants()` + `Room.getPowerLevelByUserId(userId)`.
/// Will be upgraded to the full `KoheraRoomMember` from #706 when
/// that lands.
@immutable
class KoheraRoomMember {
  const KoheraRoomMember({
    required this.userId,
    required this.powerLevel,
    this.displayName,
  });

  final String userId;
  final String? displayName;
  final int powerLevel;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KoheraRoomMember && userId == other.userId;

  @override
  int get hashCode => userId.hashCode;

  @override
  String toString() =>
      'KoheraRoomMember(userId: $userId, displayName: $displayName, '
      'powerLevel: $powerLevel)';
}

// ── KoheraRoomPermissions ─────────────────────────────────────

/// Pre-computed room permissions and admin settings data.
///
/// Created by [RoomPermissionsResolver] at the conversion boundary
/// from `matrix_sdk.Room`. Widgets below the boundary consume this
/// model and action callbacks — never `Room` directly.
@immutable
class KoheraRoomPermissions {
  const KoheraRoomPermissions({
    required this.roomId,
    required this.canEditName,
    required this.canEditTopic,
    required this.canEditAvatar,
    required this.canInvite,
    required this.canChangeJoinRules,
    required this.canChangePowerLevels,
    required this.canEnableEncryption,
    required this.isEncrypted,
    required this.powerLevelsContent,
    required this.participants,
    required this.myPowerLevel,
    this.displayName,
    this.topic,
    this.joinRule,
  });

  /// The Matrix room ID (e.g. `!abc:example.com`).
  final String roomId;

  /// Current display name (for admin settings text controllers).
  final String? displayName;

  /// Current topic (for admin settings text controllers).
  final String? topic;

  /// Whether the local user can change the room name.
  final bool canEditName;

  /// Whether the local user can change the room topic.
  final bool canEditTopic;

  /// Whether the local user can change the room avatar.
  final bool canEditAvatar;

  /// Whether the local user can invite users.
  final bool canInvite;

  /// Whether the local user can change join rules.
  final bool canChangeJoinRules;

  /// Whether the local user can change power levels.
  final bool canChangePowerLevels;

  /// Whether the local user can enable encryption (not already encrypted
  /// and has permission to change the encryption state event).
  final bool canEnableEncryption;

  /// The current join rule, or `null` if not set.
  final KoheraJoinRule? joinRule;

  /// Whether the room is end-to-end encrypted.
  final bool isEncrypted;

  /// Raw `m.room.power_levels` event content. Used by the "Who can…"
  /// section, danger zone, and advanced editor.
  final Map<String, Object?> powerLevelsContent;

  /// Room participants with their computed power levels.
  final List<KoheraRoomMember> participants;

  /// The local user's power level in this room.
  final int myPowerLevel;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KoheraRoomPermissions && roomId == other.roomId;

  @override
  int get hashCode => roomId.hashCode;

  KoheraRoomPermissions copyWith({
    String? roomId,
    String? displayName,
    String? topic,
    bool? canEditName,
    bool? canEditTopic,
    bool? canEditAvatar,
    bool? canInvite,
    bool? canChangeJoinRules,
    bool? canChangePowerLevels,
    bool? canEnableEncryption,
    KoheraJoinRule? joinRule,
    bool? isEncrypted,
    Map<String, Object?>? powerLevelsContent,
    List<KoheraRoomMember>? participants,
    int? myPowerLevel,
  }) =>
      KoheraRoomPermissions(
        roomId: roomId ?? this.roomId,
        displayName: displayName ?? this.displayName,
        topic: topic ?? this.topic,
        canEditName: canEditName ?? this.canEditName,
        canEditTopic: canEditTopic ?? this.canEditTopic,
        canEditAvatar: canEditAvatar ?? this.canEditAvatar,
        canInvite: canInvite ?? this.canInvite,
        canChangeJoinRules: canChangeJoinRules ?? this.canChangeJoinRules,
        canChangePowerLevels: canChangePowerLevels ?? this.canChangePowerLevels,
        canEnableEncryption: canEnableEncryption ?? this.canEnableEncryption,
        joinRule: joinRule ?? this.joinRule,
        isEncrypted: isEncrypted ?? this.isEncrypted,
        powerLevelsContent: powerLevelsContent ?? this.powerLevelsContent,
        participants: participants ?? this.participants,
        myPowerLevel: myPowerLevel ?? this.myPowerLevel,
      );

  @override
  String toString() =>
      'KoheraRoomPermissions(roomId: $roomId, canEditName: $canEditName, '
      'canChangePowerLevels: $canChangePowerLevels, isEncrypted: '
      '$isEncrypted, joinRule: $joinRule)';
}
